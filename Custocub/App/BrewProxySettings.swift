import Foundation

/// Homebrew 可使用的代理协议。
enum BrewProxyKind: String, CaseIterable, Identifiable, Sendable {
    case socks5
    case http

    var id: String { rawValue }

    var title: String {
        switch self {
        case .socks5: "SOCKS5"
        case .http: "HTTP"
        }
    }

    /// 实际传给下载工具（curl / git）的 scheme。
    ///
    /// SOCKS5 使用 `socks5h`，让域名解析也经过代理。只写 `socks5` 时
    /// curl 会在本地解析域名，部分下载域名（例如 GitHub 的
    /// pkg-containers.githubusercontent.com）可能解析失败。
    var urlScheme: String {
        switch self {
        case .socks5: "socks5h"
        case .http: "http"
        }
    }

    /// 界面上展示的写法，保持用户熟悉的 `socks5://`。
    var displayScheme: String {
        switch self {
        case .socks5: "socks5"
        case .http: "http"
        }
    }

    var defaultPort: Int {
        switch self {
        case .socks5: 1080
        case .http: 8080
        }
    }
}

/// Homebrew 的代理配置，保存在 UserDefaults 中。
///
/// 代理会通过环境变量传给 `brew` 以及它派生的 `git`、`curl`；
/// 「探索」目录的下载则通过 URLSession 的代理字典走同一条通道。
/// 这里只影响 Custocub 启动的进程，不会修改系统或 Git 的配置。
struct BrewProxySettings: Equatable, Sendable {
    var isEnabled: Bool
    var kind: BrewProxyKind
    var host: String
    var port: String
    /// 是否让应用代理覆盖 brew 子进程的 Git 代理配置。
    var overridesGitProxy: Bool = false

    /// `@AppStorage` 与读取逻辑共用的键。
    enum Keys {
        static let enabled = "brewProxyEnabled"
        static let kind = "brewProxyKind"
        static let host = "brewProxyHost"
        static let port = "brewProxyPort"
        static let overrideGit = "brewProxyOverrideGit"
    }

    /// 界面与本机读取共用的默认端口文本，避免两边不一致。
    static let defaultPortText = String(BrewProxyKind.socks5.defaultPort)

    static let fallback = BrewProxySettings(
        isEnabled: false,
        kind: .socks5,
        host: "",
        port: defaultPortText,
        overridesGitProxy: false
    )

    static func load(from defaults: UserDefaults = .standard) -> BrewProxySettings {
        let kind = BrewProxyKind(rawValue: defaults.string(forKey: Keys.kind) ?? "") ?? .socks5
        return BrewProxySettings(
            isEnabled: defaults.object(forKey: Keys.enabled) as? Bool ?? false,
            kind: kind,
            host: defaults.string(forKey: Keys.host) ?? "",
            port: defaults.string(forKey: Keys.port) ?? defaultPortText,
            overridesGitProxy: defaults.object(forKey: Keys.overrideGit) as? Bool ?? false
        )
    }

    static var current: BrewProxySettings { load() }

    /// 解析后的主机与端口。主机字段允许直接粘贴 `socks5://host:port`。
    var endpoint: (host: String, port: Int)? {
        var raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if let schemeRange = raw.range(of: "://") {
            raw = String(raw[schemeRange.upperBound...])
        }
        if let slash = raw.firstIndex(of: "/") {
            raw = String(raw[..<slash])
        }
        raw = raw.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }

        var hostPart = raw
        var portPart = port.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.hasPrefix("[") {
            // IPv6 字面量：[::1]:1080
            guard let closing = raw.firstIndex(of: "]") else { return nil }
            hostPart = String(raw[raw.index(after: raw.startIndex)..<closing])
            let remainder = raw[raw.index(after: closing)...]
            if remainder.hasPrefix(":") {
                portPart = String(remainder.dropFirst())
            }
        } else if let colon = raw.lastIndex(of: ":"), raw.filter({ $0 == ":" }).count == 1 {
            let candidate = String(raw[raw.index(after: colon)...])
            if Int(candidate) != nil {
                hostPart = String(raw[..<colon])
                portPart = candidate
            }
        }

        guard !hostPart.isEmpty,
              let resolvedPort = Int(portPart),
              (1...65535).contains(resolvedPort) else {
            return nil
        }
        return (hostPart, resolvedPort)
    }

    /// 是否已经填写了可用的主机与端口。
    var isConfigured: Bool { proxyURL != nil }

    /// 是否应该实际应用代理。
    var isActive: Bool { isEnabled && isConfigured }

    var proxyURL: URL? {
        guard let endpoint else { return nil }
        // URLComponents 不接受未加方括号的 IPv6 字面量，这里手动拼接。
        let hostText = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        return URL(string: "\(kind.urlScheme)://\(hostText):\(endpoint.port)")
    }

    var displayText: String {
        guard let endpoint else { return L.t("尚未配置") }
        let hostText = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        return "\(kind.displayScheme)://\(hostText):\(endpoint.port)"
    }

    /// 传给 `brew` 及其子进程的环境变量。
    ///
    /// Homebrew 官方文档推荐使用小写变量名；这里同时写入大写形式，
    /// 以兼容只读取其中一种写法的工具。
    var environmentOverrides: [String: String] {
        guard isActive, let proxyURL = proxyURL?.absoluteString else { return [:] }
        switch kind {
        case .socks5:
            return [
                "ALL_PROXY": proxyURL,
                "all_proxy": proxyURL
            ]
        case .http:
            return [
                "HTTP_PROXY": proxyURL,
                "http_proxy": proxyURL,
                "HTTPS_PROXY": proxyURL,
                "https_proxy": proxyURL
            ]
        }
    }

    /// 给 brew 子进程注入命令级 Git 配置，让 `git fetch` 也使用应用代理。
    ///
    /// Git 配置的优先级高于 `http_proxy` / `all_proxy` 环境变量，
    /// 所以只设置环境变量时 `brew update` 仍会使用 `git config` 里的代理。
    /// 这里通过 `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n`
    /// 在进程内追加配置，优先级高于全局配置，且不会写入任何配置文件。
    ///
    /// - Parameter environment: 当前进程环境，用于保留已有的 `GIT_CONFIG_*` 条目。
    /// - Parameter additionalKeys: 需要一并覆盖的 Git 配置键，例如
    ///   `http.https://github.com.proxy` 这种按 URL 单独设置的代理。
    func gitProxyEnvironment(
        merging environment: [String: String],
        additionalKeys: [String] = []
    ) -> [String: String] {
        guard isActive, overridesGitProxy, let proxyURL = proxyURL?.absoluteString else {
            return [:]
        }

        var count = Int(environment["GIT_CONFIG_COUNT"] ?? "") ?? 0
        var overrides: [String: String] = [:]

        // `https.proxy` 不是 Git 的正式键，但不少配置里会同时写下它；
        // 一并覆盖，避免界面显示和实际行为不一致。
        var keys = ["http.proxy", "https.proxy"]
        for key in additionalKeys where !key.isEmpty && !keys.contains(key) {
            keys.append(key)
        }

        for key in keys {
            overrides["GIT_CONFIG_KEY_\(count)"] = key
            overrides["GIT_CONFIG_VALUE_\(count)"] = proxyURL
            count += 1
        }
        overrides["GIT_CONFIG_COUNT"] = String(count)
        return overrides
    }

    /// URLSession 使用的代理字典。
    var connectionProxyDictionary: [AnyHashable: Any]? {
        guard isActive, let endpoint else { return nil }
        switch kind {
        case .socks5:
            return [
                "SOCKSEnable": 1,
                "SOCKSProxy": endpoint.host,
                "SOCKSPort": endpoint.port
            ]
        case .http:
            return [
                "HTTPEnable": 1,
                "HTTPProxy": endpoint.host,
                "HTTPPort": endpoint.port,
                "HTTPSEnable": 1,
                "HTTPSProxy": endpoint.host,
                "HTTPSPort": endpoint.port
            ]
        }
    }

    /// 使用当前代理访问 Homebrew API 的根地址，验证连通性。
    func testConnection() async -> BrewProxyTestResult {
        guard let dictionary = connectionProxyDictionary else {
            return .failure(L.t("请先启用代理并填写主机和端口。"))
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = dictionary
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: URL(string: "https://formulae.brew.sh/")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.setValue("Custocub/1.0", forHTTPHeaderField: "User-Agent")

        let started = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return .failure(L.t("没有收到 HTTP 响应。"))
            }
            guard (200..<400).contains(http.statusCode) else {
                return .failure(L.t("服务器返回 HTTP %d。", http.statusCode))
            }
            return .success(milliseconds: elapsed)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

/// 代理连通性测试结果。
enum BrewProxyTestResult: Equatable, Sendable {
    case success(milliseconds: Int)
    case failure(String)
}
