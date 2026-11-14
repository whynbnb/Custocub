import Foundation

/// 读取 Homebrew 全量目录与下载量统计。
///
/// 数据来源与 Homebrew 源码里的实现一致：
/// - `Library/Homebrew/api/formula.rb` / `cask.rb` 使用
///   `formula.jws.json` / `cask.jws.json`；这里用同样内容、
///   但无需验签的公开 `formula.json` / `cask.json`。
/// - `Library/Homebrew/api/analytics.rb` 与 `cmd/formula-analytics.rb`
///   使用 `analytics/install/<days>d.json` 和
///   `analytics/cask-install/<days>d.json`，天数只支持 30 / 90 / 365。
///
/// 结果写入磁盘缓存，避免每次打开「探索」都重新下载十几 MB。
enum BrewCatalogService {
    // MARK: - 缓存策略

    /// 目录（包名、描述、版本）每天更新一次足够。
    static let catalogTTL: TimeInterval = 24 * 60 * 60
    /// 下载量统计按小时更新，与 Homebrew 对未签名接口的校验频率一致。
    static let popularityTTL: TimeInterval = 60 * 60

    static let cacheDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent("BrewCatalog", isDirectory: true)
    }()

    private static var catalogFileURL: URL { cacheDirectory.appendingPathComponent("catalog.json") }
    private static var popularityFileURL: URL { cacheDirectory.appendingPathComponent("popularity.json") }

    // MARK: - 接口

    /// 是否应该跳过下载。
    private static func isFresh(_ fetchedAt: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) < ttl
    }

    /// 读取目录。命中缓存且未过期时不会联网。
    static func loadCatalog(force: Bool = false) async -> BrewCatalogCache? {
        if !force, let cached = readCatalogCache(), isFresh(cached.fetchedAt, ttl: catalogTTL) {
            return cached
        }

        if let downloaded = await downloadCatalog() {
            write(downloaded, to: catalogFileURL)
            return downloaded
        }

        // 下载失败时退回旧缓存：宁可显示过期数据，也不要空列表。
        return readCatalogCache()
    }

    /// 读取三档下载量统计。命中缓存且未过期时不会联网。
    static func loadPopularity(force: Bool = false) async -> BrewPopularitySnapshot? {
        if !force, let cached = readPopularityCache(), isFresh(cached.fetchedAt, ttl: popularityTTL) {
            return cached
        }

        if let downloaded = await downloadPopularity() {
            write(downloaded, to: popularityFileURL)
            return downloaded
        }

        return readPopularityCache()
    }

    /// 缓存是否已存在，用于首帧判断是否需要显示加载状态。
    static var hasCachedCatalog: Bool {
        FileManager.default.fileExists(atPath: catalogFileURL.path)
    }

    static func cachedCatalog() -> BrewCatalogCache? {
        readCatalogCache()
    }

    static func cachedPopularity() -> BrewPopularitySnapshot? {
        readPopularityCache()
    }

    // MARK: - 下载

    private static func downloadCatalog() async -> BrewCatalogCache? {
        // 串行下载与解码：两个文件解压后合计约 50 MB，
        // 并发解码会让峰值内存翻倍。串行反而更稳。
        guard let formulaData = await fetch("formula.json") else { return nil }
        let formulae = await Task.detached(priority: .userInitiated) {
            decodeFormulae(formulaData)
        }.value
        guard !formulae.isEmpty else { return nil }

        guard let caskData = await fetch("cask.json") else { return nil }
        let casks = await Task.detached(priority: .userInitiated) {
            decodeCasks(caskData)
        }.value
        guard !casks.isEmpty else { return nil }

        return BrewCatalogCache(entries: formulae + casks, fetchedAt: Date())
    }

    private static func downloadPopularity() async -> BrewPopularitySnapshot? {
        var snapshot = BrewPopularitySnapshot(rankings: [:], fetchedAt: Date())

        // 6 个请求并发执行；某个失败时只保留成功的部分。
        await withTaskGroup(of: (BrewAnalyticsRange, BrewPackageKind, BrewPopularityRanking?).self) { group in
            for range in BrewAnalyticsRange.allCases {
                group.addTask {
                    (range, .formula, await fetchRanking(category: "install", range: range))
                }
                group.addTask {
                    (range, .cask, await fetchRanking(category: "cask-install", range: range))
                }
            }

            for await (range, kind, ranking) in group {
                guard let ranking else { continue }
                snapshot.setRanking(ranking, range: range, kind: kind)
            }
        }

        guard !snapshot.isEmpty else { return nil }
        return snapshot
    }

    private static func fetchRanking(category: String, range: BrewAnalyticsRange) async -> BrewPopularityRanking? {
        guard let data = await fetch("analytics/\(category)/\(range.rawValue).json") else { return nil }
        return await Task.detached(priority: .utility) {
            decodeRanking(data)
        }.value
    }

    // MARK: - 网络

    private static func fetch(_ endpoint: String) async -> Data? {
        guard let url = URL(string: "https://formulae.brew.sh/api/\(endpoint)") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Custocub/1.0", forHTTPHeaderField: "User-Agent")

        // 与 brew 命令共用设置里的代理配置。
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        if let proxyDictionary = BrewProxySettings.current.connectionProxyDictionary {
            configuration.connectionProxyDictionary = proxyDictionary
        }
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - 解析

    /// 只解码探索需要的字段。
    /// `formula.json` 解压后约 31 MB，用精简的 Decodable 比
    /// `JSONSerialization` + 字典转换快一倍，峰值内存也更低。
    private struct RawFormula: Decodable {
        let name: String
        let fullName: String?
        let tap: String?
        let desc: String?
        let homepage: String?
        let license: String?
        let aliases: [String]?
        let oldnames: [String]?
        let deprecated: Bool?
        let disabled: Bool?
        let versions: Versions?

        struct Versions: Decodable {
            let stable: String?
        }

        enum CodingKeys: String, CodingKey {
            case name, tap, desc, homepage, license, aliases, oldnames, deprecated, disabled, versions
            case fullName = "full_name"
        }
    }

    private struct RawCask: Decodable {
        let token: String
        let fullToken: String?
        let tap: String?
        let desc: String?
        let homepage: String?
        let version: String?
        let name: [String]?
        let oldTokens: [String]?
        let deprecated: Bool?
        let disabled: Bool?

        enum CodingKeys: String, CodingKey {
            case token, tap, desc, homepage, version, name, deprecated, disabled
            case fullToken = "full_token"
            case oldTokens = "old_tokens"
        }
    }

    private struct RawAnalytics: Decodable {
        struct Item: Decodable {
            let number: Int?
            let name: String?
            let formula: String?
            let cask: String?
            let count: String?
            let percent: String?
        }

        let category: String?
        let total_items: Int?
        let start_date: String?
        let end_date: String?
        let total_count: Int?
        let items: [Item]
    }

    private static func decodeFormulae(_ data: Data) -> [BrewCatalogEntry] {
        guard let raw = try? JSONDecoder().decode([RawFormula].self, from: data) else { return [] }
        return raw.map { item in
            BrewCatalogEntry(
                kind: .formula,
                name: item.name,
                fullName: item.fullName,
                displayName: nil,
                summary: item.desc,
                homepage: item.homepage,
                license: item.license,
                tap: item.tap,
                latestVersion: item.versions?.stable,
                aliases: (item.aliases ?? []) + (item.oldnames ?? []),
                isDeprecated: item.deprecated ?? false,
                isDisabled: item.disabled ?? false
            )
        }
    }

    private static func decodeCasks(_ data: Data) -> [BrewCatalogEntry] {
        guard let raw = try? JSONDecoder().decode([RawCask].self, from: data) else { return [] }
        return raw.map { item in
            BrewCatalogEntry(
                kind: .cask,
                name: item.token,
                fullName: item.fullToken,
                displayName: item.name?.first,
                summary: item.desc,
                homepage: item.homepage,
                license: nil,
                tap: item.tap,
                latestVersion: item.version,
                aliases: item.oldTokens ?? [],
                isDeprecated: item.deprecated ?? false,
                isDisabled: item.disabled ?? false
            )
        }
    }

    /// 解析 `analytics/*.json`。
    private static func decodeRanking(_ data: Data) -> BrewPopularityRanking? {
        guard let raw = try? JSONDecoder().decode(RawAnalytics.self, from: data) else { return nil }

        var counts: [String: Int] = [:]
        var ranks: [String: Int] = [:]

        for item in raw.items {
            guard let name = item.formula ?? item.cask else { continue }
            // 只统计核心仓库：第三方 tap 的条目没有目录信息，无法展示。
            guard !name.contains("/") else { continue }

            let value = Int((item.count ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
            counts[name] = value
            if let number = item.number {
                ranks[name] = number
            }
        }

        guard !counts.isEmpty else { return nil }

        return BrewPopularityRanking(
            counts: counts,
            ranks: ranks,
            totalCount: raw.total_count ?? 0,
            startDate: raw.start_date,
            endDate: raw.end_date
        )
    }

    // MARK: - 磁盘

    private static func readCatalogCache() -> BrewCatalogCache? {
        guard let data = try? Data(contentsOf: catalogFileURL) else { return nil }
        return try? JSONDecoder().decode(BrewCatalogCache.self, from: data)
    }

    private static func readPopularityCache() -> BrewPopularitySnapshot? {
        guard let data = try? Data(contentsOf: popularityFileURL) else { return nil }
        return try? JSONDecoder().decode(BrewPopularitySnapshot.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[Custocub] 无法写入 Homebrew 目录缓存 \(url.lastPathComponent): \(error)")
        }
    }

    /// 清除缓存，设置界面提供入口。
    static func clearCache() {
        try? FileManager.default.removeItem(at: catalogFileURL)
        try? FileManager.default.removeItem(at: popularityFileURL)
    }
}
