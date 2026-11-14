import Foundation

/// 下载量统计的时间范围。与 `brew formula-analytics --days` 支持的取值一致：
/// Homebrew 只提供 30、90、365 天三档匿名统计数据。
enum BrewAnalyticsRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case month = "30d"
    case quarter = "90d"
    case year = "365d"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .month: 30
        case .quarter: 90
        case .year: 365
        }
    }

    var title: String {
        L.t("近 %d 天", days)
    }
}

/// 探索列表的排序方式。
enum BrewCatalogSort: String, CaseIterable, Identifiable, Sendable {
    case popularity
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popularity: L.t("下载量")
        case .name: L.t("名称")
        }
    }

    var symbol: String {
        switch self {
        case .popularity: "chart.bar.fill"
        case .name: "textformat.abc"
        }
    }
}

/// 探索列表一次展示多少条。
enum BrewCatalogLimit: Int, CaseIterable, Identifiable, Sendable {
    case fifty = 50
    case hundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case all = 0

    var id: Int { rawValue }

    var title: String {
        self == .all ? L.t("全部") : L.t("前 %d 个", rawValue)
    }

    /// 是否限制条数。`nil` 表示不限制。
    var count: Int? {
        self == .all ? nil : rawValue
    }
}

/// Homebrew 全量目录中的一个包。
///
/// 和 `BrewPackage` 的区别：`BrewPackage` 描述本机**已安装**的包，
/// 这里描述 Homebrew 仓库里**所有**可安装的 Formula 与 Cask，
/// 即使本机没有安装也可能出现在「探索」中。
struct BrewCatalogEntry: Identifiable, Codable, Hashable, Sendable {
    var kind: BrewPackageKind
    var name: String
    var fullName: String
    var displayName: String?
    var summary: String?
    var homepage: String?
    var license: String?
    var tap: String?
    var latestVersion: String?
    var aliases: [String]
    var isDeprecated: Bool
    var isDisabled: Bool

    /// 预先拼接好的小写搜索文本。
    ///
    /// 上万个包、每次按键都要过滤一遍，用 `localizedCaseInsensitiveContains`
    /// 逐个字段比较会明显卡顿；这里在载入时拼一次，之后只做一次 `contains`。
    /// 不写入缓存文件：解码时重新生成。
    private(set) var searchBlob: String = ""

    var id: String { "\(kind.rawValue):\(name)" }

    /// 列表显示名：Cask 优先使用产品名，例如 `firefox` -> `Mozilla Firefox`。
    var title: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }

    /// 是否已停止维护。仍然展示，但用徽章提示。
    var isDeprecatedOrDisabled: Bool { isDeprecated || isDisabled }

    var installCommand: String {
        BrewPackage.command("install", kind: kind, names: [name])
    }

    var uninstallCommand: String {
        BrewPackage.command("uninstall", kind: kind, names: [name])
    }

    var infoCommand: String {
        "brew info \(name)"
    }

    var tapText: String {
        tap ?? L.t("未知")
    }

    /// 是否匹配搜索关键词。名称、产品名、别名、描述、tap 都参与匹配。
    func matches(query: String) -> Bool {
        matches(lowercasedQuery: query.lowercased())
    }

    /// 已经转成小写的关键词。批量筛选时只转一次。
    func matches(lowercasedQuery: String) -> Bool {
        guard !lowercasedQuery.isEmpty else { return true }
        return searchBlob.contains(lowercasedQuery)
    }

    init(
        kind: BrewPackageKind,
        name: String,
        fullName: String? = nil,
        displayName: String? = nil,
        summary: String? = nil,
        homepage: String? = nil,
        license: String? = nil,
        tap: String? = nil,
        latestVersion: String? = nil,
        aliases: [String] = [],
        isDeprecated: Bool = false,
        isDisabled: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.fullName = fullName ?? name
        self.displayName = displayName
        self.summary = summary
        self.homepage = homepage
        self.license = license
        self.tap = tap
        self.latestVersion = latestVersion
        self.aliases = aliases
        self.isDeprecated = isDeprecated
        self.isDisabled = isDisabled
        self.searchBlob = Self.makeSearchBlob(
            name: name,
            fullName: fullName ?? name,
            displayName: displayName,
            summary: summary,
            tap: tap,
            latestVersion: latestVersion,
            aliases: aliases
        )
    }

    private static func makeSearchBlob(
        name: String,
        fullName: String,
        displayName: String?,
        summary: String?,
        tap: String?,
        latestVersion: String?,
        aliases: [String]
    ) -> String {
        var parts: [String] = [name, fullName]
        if let displayName { parts.append(displayName) }
        if let summary { parts.append(summary) }
        if let tap { parts.append(tap) }
        if let latestVersion { parts.append(latestVersion) }
        parts.append(contentsOf: aliases)
        return parts.joined(separator: "\n").lowercased()
    }

    /// 缓存文件只保存目录信息，下载量单独存放在另一个文件里。
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case fullName
        case displayName
        case summary
        case homepage
        case license
        case tap
        case latestVersion
        case aliases
        case isDeprecated
        case isDisabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(BrewPackageKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName) ?? name
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        homepage = try container.decodeIfPresent(String.self, forKey: .homepage)
        license = try container.decodeIfPresent(String.self, forKey: .license)
        tap = try container.decodeIfPresent(String.self, forKey: .tap)
        latestVersion = try container.decodeIfPresent(String.self, forKey: .latestVersion)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        isDeprecated = try container.decodeIfPresent(Bool.self, forKey: .isDeprecated) ?? false
        isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled) ?? false
        searchBlob = Self.makeSearchBlob(
            name: name,
            fullName: fullName,
            displayName: displayName,
            summary: summary,
            tap: tap,
            latestVersion: latestVersion,
            aliases: aliases
        )
    }
}

/// 一个时间范围内、某一类包（Formula 或 Cask）的下载量统计。
///
/// 数据来自 `https://formulae.brew.sh/api/analytics/{install,cask-install}/<range>.json`，
/// 与 `brew formula-analytics` 使用同一份匿名统计。
struct BrewPopularityRanking: Codable, Sendable, Hashable {
    /// 包名 -> 下载量。
    var counts: [String: Int]
    /// 包名 -> 该分类下的排名（来自 API 的 `number` 字段）。
    var ranks: [String: Int]
    /// 该分类的全部下载量，包含第三方 tap，因此核心仓库占比合计小于 100%。
    var totalCount: Int
    var startDate: String?
    var endDate: String?

    func count(for entry: BrewCatalogEntry) -> Int {
        counts[entry.name] ?? 0
    }

    /// 在同类包中的排名。没有统计时为 nil。
    func rank(for entry: BrewCatalogEntry) -> Int? {
        ranks[entry.name]
    }

    func percent(for entry: BrewCatalogEntry) -> Double {
        guard totalCount > 0 else { return 0 }
        return Double(count(for: entry)) / Double(totalCount)
    }

    /// 下载量文本，带千分位。
    func countText(for entry: BrewCatalogEntry) -> String {
        count(for: entry).formatted(.number.grouping(.automatic))
    }

    func percentText(for entry: BrewCatalogEntry) -> String {
        let value = percent(for: entry) * 100
        if value == 0 { return "—" }
        if value < 0.01 { return "<0.01%" }
        return String(format: "%.2f%%", value)
    }

    var dateRangeText: String? {
        guard let startDate, let endDate else { return nil }
        return L.t("%@ 至 %@", startDate, endDate)
    }
}

/// 三档时间范围、两类包的下载量快照。
///
/// 一次性读取 6 份数据，切换时间范围时不需要重新联网。
struct BrewPopularitySnapshot: Codable, Sendable {
    /// key 形如 `30d:formula`、`365d:cask`。
    var rankings: [String: BrewPopularityRanking]
    var fetchedAt: Date

    private static func key(_ range: BrewAnalyticsRange, _ kind: BrewPackageKind) -> String {
        "\(range.rawValue):\(kind.rawValue)"
    }

    func ranking(for range: BrewAnalyticsRange, kind: BrewPackageKind) -> BrewPopularityRanking? {
        rankings[Self.key(range, kind)]
    }

    mutating func setRanking(_ ranking: BrewPopularityRanking, range: BrewAnalyticsRange, kind: BrewPackageKind) {
        rankings[Self.key(range, kind)] = ranking
    }

    var isEmpty: Bool { rankings.isEmpty }
}

/// 磁盘上的目录缓存。
struct BrewCatalogCache: Codable, Sendable {
    var entries: [BrewCatalogEntry]
    var fetchedAt: Date
}

/// 探索列表的筛选与排序条件。
///
/// 独立成值类型，方便单测，也让 `BrewStore` 里只保留一行调用。
struct BrewCatalogQuery: Sendable, Equatable {
    var searchText: String = ""
    var kind: BrewPackageKind?
    var range: BrewAnalyticsRange = .month
    var sort: BrewCatalogSort = .popularity
    var limit: BrewCatalogLimit = .hundred
    var showsDeprecated = true

    /// 应用筛选并排序。
    ///
    /// 按下载量排序时截断到 `limit`；输入搜索关键词时总是返回全部匹配项，
    /// 因为用户明确在找某个包，不该被条数限制挡住。
    func apply(to entries: [BrewCatalogEntry], popularity: BrewPopularitySnapshot?) -> [BrewCatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuery = query.lowercased()

        let filtered = entries.filter { entry in
            let matchesKind = kind == nil || entry.kind == kind
            let matchesDeprecated = showsDeprecated || !entry.isDeprecatedOrDisabled
            return matchesKind && matchesDeprecated && entry.matches(lowercasedQuery: lowercasedQuery)
        }

        switch sort {
        case .popularity:
            // 预先算出每个包的下载量，避免排序时反复查字典。
            let formulaCounts = popularity?.ranking(for: range, kind: .formula)?.counts ?? [:]
            let caskCounts = popularity?.ranking(for: range, kind: .cask)?.counts ?? [:]

            func downloads(_ entry: BrewCatalogEntry) -> Int {
                switch entry.kind {
                case .formula: formulaCounts[entry.name] ?? 0
                case .cask: caskCounts[entry.name] ?? 0
                }
            }

            let counts = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, downloads($0)) })

            if query.isEmpty, let limit = limit.count {
                // 只需要前 N 个时做部分选择，比全量排序快一个数量级。
                return Self.top(filtered, limit: limit) { counts[$0.id] ?? 0 }
            }

            return filtered.sorted { lhs, rhs in
                let left = counts[lhs.id] ?? 0
                let right = counts[rhs.id] ?? 0
                if left != right { return left > right }
                return lhs.name < rhs.name
            }
        case .name:
            return filtered.sorted { $0.name < $1.name }
        }
    }

    /// 取下载量最大的前 N 个。使用最小堆，避免对上万个包做完整排序。
    private static func top(
        _ entries: [BrewCatalogEntry],
        limit: Int,
        by value: (BrewCatalogEntry) -> Int
    ) -> [BrewCatalogEntry] {
        guard limit > 0, entries.count > limit else {
            return entries.sorted { lhs, rhs in
                let left = value(lhs), right = value(rhs)
                if left != right { return left > right }
                return lhs.name < rhs.name
            }
        }

        var heap: [(entry: BrewCatalogEntry, value: Int)] = []
        heap.reserveCapacity(limit)

        for entry in entries {
            let current = value(entry)
            if heap.count < limit {
                heap.append((entry, current))
                if heap.count == limit {
                    heap.sort { $0.value < $1.value }
                }
            } else if current > heap[0].value {
                heap[0] = (entry, current)
                // 重新下沉堆顶。
                var index = 0
                while true {
                    let left = index * 2 + 1
                    let right = index * 2 + 2
                    var smallest = index
                    if left < heap.count, heap[left].value < heap[smallest].value { smallest = left }
                    if right < heap.count, heap[right].value < heap[smallest].value { smallest = right }
                    if smallest == index { break }
                    heap.swapAt(index, smallest)
                    index = smallest
                }
            }
        }

        return heap
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.entry.name < rhs.entry.name
            }
            .map(\.entry)
    }

    /// 是否有任何条件处于非默认状态。
    var isActive: Bool {
        kind != nil
            || !showsDeprecated
            || sort != .popularity
            || limit != .hundred
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
