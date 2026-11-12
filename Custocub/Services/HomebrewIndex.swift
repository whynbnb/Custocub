import Foundation

/// 启动时一次性建立 Homebrew Cask 索引，避免为每个应用执行 brew 命令。
struct HomebrewIndex: Sendable {
    static let caskroomRoots = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom",
        "/home/linuxbrew/.linuxbrew/Caskroom"
    ]

    let appNames: Set<String>
    let caskNames: Set<String>
    /// pkg 安装型 cask 实际写入 `/Applications` 的 .app 路径。
    /// 例如 karabiner-elements 的 pkg 同时安装了 Karabiner-Elements.app
    /// 和 Karabiner-EventViewer.app，但 Caskroom 里只有 .pkg。
    let installedAppPaths: Set<String>

    static func build() -> HomebrewIndex {
        let fileManager = FileManager.default
        var appNames = Set<String>()
        var caskNames = Set<String>()
        var installedAppPaths = Set<String>()
        var receiptIndex: ReceiptIndex?

        for root in caskroomRoots where fileManager.fileExists(atPath: root) {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)

            // Cask 目录名就是 cask token。
            if let casks = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for cask in casks {
                    caskNames.insert(cask.lastPathComponent.lowercased())
                }
            }

            // 普通 cask 会把 .app 放在 Caskroom 里（可能是符号链接）。
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                appNames.insert(url.lastPathComponent.lowercased())
                enumerator.skipDescendants()
            }

            // pkg 安装型 cask 的 .app 不在 Caskroom 里，需要通过安装收据反查。
            guard let casks = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for cask in casks {
                let receiptURL = cask
                    .appendingPathComponent(".metadata", isDirectory: true)
                    .appendingPathComponent("INSTALL_RECEIPT.json")
                guard fileManager.fileExists(atPath: receiptURL.path) else { continue }

                if receiptIndex == nil {
                    receiptIndex = ReceiptIndex()
                }
                installedAppPaths.formUnion(
                    receiptIndex?.appPaths(inReceipt: receiptURL) ?? []
                )
            }
        }

        return HomebrewIndex(
            appNames: appNames,
            caskNames: caskNames,
            installedAppPaths: installedAppPaths
        )
    }

    func contains(appURL: URL, resolvedPath: String) -> Bool {
        let resolved = resolvedPath.lowercased()
        if resolved.contains("/caskroom/") { return true }
        if appURL.path.lowercased().contains("/caskroom/") { return true }

        let original = appURL.standardizedFileURL.path.lowercased()
        if installedAppPaths.contains(original) { return true }
        if installedAppPaths.contains(resolved) { return true }

        let bundleName = appURL.lastPathComponent.lowercased()
        if appNames.contains(bundleName) { return true }

        // 某些 cask 的 app 文件名和 token 不同，但通常包含 token。
        let normalizedName = bundleName
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return caskNames.contains(normalizedName)
    }

    /// 解析 Homebrew 安装收据里的 pkgutil 收据 ID，再查询这些 pkg 安装了哪些 .app。
    private final class ReceiptIndex {
        private var filePathsByReceipt: [String: Set<String>] = [:]
        private var installedReceipts: [String]?

        private static let pkgutilPath = "/usr/sbin/pkgutil"

        func appPaths(inReceipt url: URL) -> Set<String> {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) else {
                return []
            }

            var patterns = Set<String>()
            Self.collectPkgutilIDs(from: root, into: &patterns)
            guard !patterns.isEmpty else { return [] }

            var paths = Set<String>()
            for pattern in patterns {
                for receipt in matchingReceipts(for: pattern) {
                    paths.formUnion(filesInstalledBy(receipt: receipt))
                }
            }
            return paths
        }

        private static func collectPkgutilIDs(from value: Any, into ids: inout Set<String>) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if key == "pkgutil" {
                        if let list = child as? [String] {
                            ids.formUnion(list)
                        } else if let single = child as? String {
                            ids.insert(single)
                        }
                    } else {
                        collectPkgutilIDs(from: child, into: &ids)
                    }
                }
            } else if let list = value as? [Any] {
                for child in list {
                    collectPkgutilIDs(from: child, into: &ids)
                }
            }
        }

        /// Homebrew 收据里的 ID 可能带通配符，例如 `com.microsoft.dotnet.*`。
        private func matchingReceipts(for pattern: String) -> [String] {
            if let installedReceipts, !pattern.contains("*"), !pattern.contains("?") {
                return installedReceipts.contains(pattern) ? [pattern] : []
            }

            if installedReceipts == nil {
                installedReceipts = Self.runPkgutil(arguments: ["--pkgs"])
                    .flatMap { $0.split(separator: "\n").map(String.init) }
                    ?? []
            }

            if !pattern.contains("*"), !pattern.contains("?") {
                return (installedReceipts ?? []).contains(pattern) ? [pattern] : []
            }

            let regex = Self.globRegex(for: pattern)
            return (installedReceipts ?? []).filter { $0.range(of: regex, options: .regularExpression) != nil }
        }

        private func filesInstalledBy(receipt: String) -> Set<String> {
            if let cached = filePathsByReceipt[receipt] { return cached }
            guard let output = Self.runPkgutil(arguments: ["--files", receipt]) else {
                filePathsByReceipt[receipt] = []
                return []
            }

            var paths = Set<String>()
            for line in output.split(separator: "\n") {
                let path = String(line)
                // 只关心顶层 Applications/Foo.app，忽略 pkg 内部的文件。
                guard path.hasPrefix("Applications/"),
                      path.lowercased().hasSuffix(".app") else { continue }
                let components = path.split(separator: "/")
                guard components.count == 2 else { continue }
                paths.insert("/" + path.lowercased())
            }
            filePathsByReceipt[receipt] = paths
            return paths
        }

        private static func runPkgutil(arguments: [String]) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pkgutilPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func globRegex(for pattern: String) -> String {
            var result = "^"
            for character in pattern {
                switch character {
                case "*": result += ".*"
                case "?": result += "."
                default: result += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            result += "$"
            return result
        }
    }
}
