import AppKit
import Foundation

/// 命令日志中的一条记录。
struct BrewLogEntry: Identifiable, Sendable {
    enum Level: Sendable {
        case command
        case info
        case success
        case failure
        case output
    }

    let id = UUID()
    var level: Level
    var text: String
    var date: Date = Date()

    var timeText: String {
        date.formatted(date: .omitted, time: .standard)
    }
}

/// Homebrew 管理界面的分区。
enum BrewSection: String, CaseIterable, Identifiable {
    case packages
    case explore
    case upgrade
    case snapshots
    case services
    case cleanup
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packages: L.t("包")
        case .explore: L.t("探索")
        case .upgrade: L.t("升级")
        case .snapshots: L.t("快照")
        case .services: L.t("服务")
        case .cleanup: L.t("清理")
        case .health: L.t("配置与诊断")
        }
    }

    var symbol: String {
        switch self {
        case .packages: "shippingbox"
        case .explore: "safari"
        case .upgrade: "arrow.triangle.2.circlepath"
        case .snapshots: "camera"
        case .services: "gearshape.2"
        case .cleanup: "trash"
        case .health: "stethoscope"
        }
    }
}

/// 一条可撤销/可重试的历史命令。
struct BrewCommandHistoryItem: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var commandLine: String
    var arguments: [String]
    var succeeded: Bool
    var date: Date
    var duration: TimeInterval
}

/// Homebrew 独立管理界面和命令执行的状态中心。
@MainActor
final class BrewStore: ObservableObject {
    @Published private(set) var inventory: BrewInventory?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    /// 是否真正发起过一次清单读取，用于区分「还没开始」和「读取失败」。
    @Published private(set) var hasAttemptedLoad = false
    @Published private(set) var lastLoadedAt: Date?

    @Published private(set) var snapshots: [BrewSnapshot] = []
    @Published private(set) var isSavingSnapshot = false

    @Published private(set) var isRunningCommand = false
    @Published var logEntries: [BrewLogEntry] = []
    @Published private(set) var history: [BrewCommandHistoryItem] = []
    @Published var selectedPackageID: String?
    @Published var errorMessage: String?

    /// 清理分析结果（缓存、旧版本、无用依赖等）。
    @Published private(set) var cleanupReport: BrewCleanupReport?
    @Published private(set) var isAnalyzingCleanup = false
    @Published private(set) var lastCleanupAnalyzedAt: Date?
    /// 上次清理释放的空间，用于在界面上反馈结果。
    @Published private(set) var lastCleanupFreedBytes: Int64?

    /// `brew config` 的解析结果。
    @Published private(set) var configInfo: BrewConfigInfo?
    @Published private(set) var isLoadingConfig = false
    private var configTask: Task<Void, Never>?
    /// `brew doctor` 的诊断结果。
    @Published private(set) var doctorReport: BrewDoctorReport?
    @Published private(set) var isRunningDoctor = false
    private var doctorTask: Task<Void, Never>?

    /// 可被 `brew services` 管理的后台服务。
    @Published private(set) var serviceEntries: [BrewServiceInfo] = []
    @Published private(set) var isLoadingServices = false
    @Published private(set) var lastServicesLoadedAt: Date?
    private var servicesTask: Task<Void, Never>?

    @Published var searchText = ""
    @Published var kindFilter: BrewPackageKind?
    @Published var showsOutdatedOnly = false
    @Published var showsPinnedOnly = false
    /// 是否显示「只作为依赖安装」的 formula。默认显示，取消勾选后只看主动安装的包。
    @Published var showsDependencyPackages = true

    @Published var section: BrewSection = .packages
    @Published var selection: Set<String> = [] {
        didSet {
            if selection.count == 1 {
                selectedPackageID = selection.first
            } else if selection.isEmpty {
                selectedPackageID = nil
            }
        }
    }

    // MARK: - 探索

    /// Homebrew 全量目录（所有可安装的 Formula 与 Cask，不只是本机已安装的）。
    @Published private(set) var catalog: [BrewCatalogEntry] = []
    /// 三档下载量统计。
    @Published private(set) var popularity: BrewPopularitySnapshot?
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var isLoadingPopularity = false
    @Published private(set) var hasLoadedCatalog = false
    /// 是否至少尝试过一次读取目录，用于区分「还没开始」和「加载失败」。
    @Published private(set) var hasAttemptedCatalogLoad = false
    @Published private(set) var lastCatalogLoadedAt: Date?
    @Published private(set) var lastPopularityLoadedAt: Date?
    /// 是否至少尝试过一次读取下载量统计。
    @Published private(set) var hasAttemptedPopularityLoad = false
    private var catalogTask: Task<Void, Never>?
    private var popularityTask: Task<Void, Never>?

    /// 探索界面的筛选条件。
    @Published var exploreSearchText = ""
    @Published var exploreKindFilter: BrewPackageKind?
    @Published var exploreRange: BrewAnalyticsRange = .month
    @Published var exploreSort: BrewCatalogSort = .popularity
    @Published var exploreLimit: BrewCatalogLimit = .hundred
    /// 是否显示已弃用（deprecated / disabled）的包。
    @Published var exploreShowsDeprecated = true
    /// 探索列表中选中的包。
    @Published var selectedCatalogEntryID: String?

    /// Homebrew 整体开关。默认开启，关闭后不执行任何 brew 命令。
    /// 只影响 Homebrew 管理功能，应用清单中的 Homebrew 来源保持不变。
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled {
                Task { await load(force: true) }
            } else {
                deactivate()
            }
        }
    }

    /// 当前升级策略。切换后会重新读取清单，
    /// 让「可更新」数量和升级列表立刻反映新的范围。
    @Published var upgradePolicy: BrewUpgradePolicy {
        didSet {
            guard upgradePolicy != oldValue else { return }
            UserDefaults.standard.set(upgradePolicy.rawValue, forKey: BrewUpgradePolicy.defaultsKey)
            guard isAvailable else { return }
            Task { await load(force: true) }
        }
    }

    /// 启动时解析一次 brew 路径，避免在视图 body 中反复访问文件系统。
    /// 关闭开关时保持路径不变，重新开启可以立刻复用。
    @Published private(set) var executableURL = BrewService.locateExecutable()

    private var runningProcess: BrewProcess?
    private let snapshotRepository = BrewSnapshotRepository()

    private static let enabledKey = "homebrewEnabled"

    /// 读取保存的开关状态，供其他组件在不持有 store 时判断。
    /// 默认开启；用户显式关闭后为 false。
    static var isEnabledPreference: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    init() {
        isEnabled = Self.isEnabledPreference
        upgradePolicy = BrewUpgradePolicy.current
        loadSnapshots()

        // 版本检测很轻量（`brew --version` 约 20ms），在 init 中同步完成，
        // 这样首帧就能给出准确的可用性判断，避免先放行再拦截的闪烁。
        detectedVersion = Self.detectVersion()
    }

    // MARK: - 状态

    /// 是否检测到 Homebrew 可执行文件。
    var isInstalled: Bool { executableURL != nil }

    /// 检测到的 Homebrew 版本。尚未检测时为 nil。
    @Published private(set) var detectedVersion: BrewVersion?

    /// 功能是否可用：开关开启、已安装、且版本满足最低要求。
    var isAvailable: Bool { isEnabled && isInstalled && isVersionSupported }

    /// 用户主动关闭时为 true。
    var isDisabledByUser: Bool { !isEnabled }

    /// 开启开关但本机未安装 Homebrew。
    var isMissingInstallation: Bool { isEnabled && !isInstalled }

    /// 已安装但版本低于最低要求。
    var isVersionUnsupported: Bool {
        isEnabled && isInstalled && detectedVersion != nil && !isVersionSupported
    }

    /// 版本是否满足最低要求。尚未检测完成时先按可用处理，避免闪烁。
    var isVersionSupported: Bool {
        detectedVersion?.isSupported ?? true
    }

    /// 展示用的版本字符串。
    var versionText: String {
        detectedVersion?.description ?? inventory?.brewVersion ?? L.t("未知")
    }

    var executablePath: String {
        executableURL?.path ?? L.t("未找到 Homebrew")
    }

    var formulae: [BrewPackage] { inventory?.formulae ?? [] }
    var casks: [BrewPackage] { inventory?.casks ?? [] }
    var packages: [BrewPackage] { inventory?.all ?? [] }

    var packageCount: Int { inventory?.packageCount ?? 0 }
    var formulaCount: Int { inventory?.formulae.count ?? 0 }
    var caskCount: Int { inventory?.casks.count ?? 0 }
    var outdatedCount: Int { inventory?.outdatedCount ?? 0 }
    var pinnedCount: Int { inventory?.pinnedCount ?? 0 }

    var brewVersion: String {
        detectedVersion?.description ?? inventory?.brewVersion ?? L.t("未知")
    }

    var prefix: String {
        inventory?.prefix ?? L.t("未知")
    }

    var dependencyCount: Int {
        formulae.count(where: \.isDependency)
    }

    // MARK: - 版本检测

    /// 启动时同步执行 `brew --version` 并解析版本号。
    ///
    /// 该命令约 20ms，直接阻塞主线程可以保证首帧就有准确的可用性判断，
    /// 避免界面先放行再拦截的闪烁。
    private static func detectVersion() -> BrewVersion? {
        detectVersionSynchronously()
    }

    static func detectVersionSynchronously() -> BrewVersion? {
        guard let executable = BrewService.locateExecutable() else { return nil }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["NONINTERACTIVE"] = "1"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        return BrewVersion(output: String(decoding: data, as: UTF8.self))
    }

    /// 重新检测版本，用于用户升级 Homebrew 后手动刷新。
    func refreshVersion() async {
        let output = await BrewService.runQuiet(arguments: ["--version"]).output
        detectedVersion = BrewVersion(output: output)

        if isVersionSupported, isAvailable {
            await load(force: true)
        }
    }

    var filteredPackages: [BrewPackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return packages.filter { package in
            let matchesKind = kindFilter == nil || package.kind == kindFilter
            let matchesOutdated = !showsOutdatedOnly || package.isOutdated
            let matchesPinned = !showsPinnedOnly || package.isPinned
            let matchesDependency = showsDependencyPackages || !package.isDependency
            let matchesSearch = query.isEmpty
                || package.name.localizedCaseInsensitiveContains(query)
                || package.title.localizedCaseInsensitiveContains(query)
                || (package.summary?.localizedCaseInsensitiveContains(query) == true)
                || (package.tap?.localizedCaseInsensitiveContains(query) == true)
                || (package.installedVersion?.localizedCaseInsensitiveContains(query) == true)
            return matchesKind && matchesOutdated && matchesPinned && matchesDependency && matchesSearch
        }
    }

    func package(id: String?) -> BrewPackage? {
        guard let id else { return nil }
        return inventory?.package(id: id)
    }

    /// 按名称查找已安装的包。依赖名可能带 tap 前缀，比较时忽略它。
    /// 同名时优先 Formula，因为 Cask 不会作为 Formula 的依赖出现。
    func package(named name: String) -> BrewPackage? {
        let key = BrewPackage.dependencyKey(for: name)
        return packages.first { $0.kind == .formula && $0.dependencyKey == key }
            ?? packages.first { $0.dependencyKey == key }
    }

    var selectedPackage: BrewPackage? {
        package(id: selectedPackageID)
    }

    /// 直接依赖指定包的所有已安装包。
    func dependents(of package: BrewPackage) -> [BrewPackage] {
        let key = package.dependencyKey
        return packages
            .filter { candidate in
                guard candidate.id != package.id else { return false }
                return candidate.dependencies.contains {
                    BrewPackage.dependencyKey(for: $0) == key
                }
            }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .formula }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// 在详情面板里跳到另一个已安装包；能保留当前筛选时就保留。
    func focusPackage(_ package: BrewPackage) {
        if filteredPackages.contains(where: { $0.id == package.id }) {
            selection = [package.id]
            selectedPackageID = package.id
        } else {
            revealPackage(package)
        }
    }

    /// 当前是否有任何筛选条件处于非默认状态。
    var hasActivePackageFilter: Bool {
        kindFilter != nil
            || showsOutdatedOnly
            || showsPinnedOnly
            || !showsDependencyPackages
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetFilters() {
        searchText = ""
        kindFilter = nil
        showsOutdatedOnly = false
        showsPinnedOnly = false
        showsDependencyPackages = true
    }

    // MARK: - 探索

    /// 当前时间范围、指定包类型的下载量统计。
    ///
    /// Homebrew 把 Formula 与 Cask 分开统计，所以同一列表里两类包的
    /// 下载量不能直接比较大小，排序时按各自的统计分别取排名。
    func ranking(for kind: BrewPackageKind) -> BrewPopularityRanking? {
        popularity?.ranking(for: exploreRange, kind: kind)
    }

    /// 当前筛选类型对应的下载量统计，用于顶部指标与详情面板。
    var activeRanking: BrewPopularityRanking? {
        ranking(for: exploreKindFilter ?? .formula)
    }

    /// 当前时间范围的总下载量。类型筛选为「全部」时，把 Formula 与 Cask 相加。
    var activeTotalDownloads: Int {
        if let kind = exploreKindFilter {
            return popularity?.ranking(for: exploreRange, kind: kind)?.totalCount ?? 0
        }
        return BrewPackageKind.allCases.reduce(0) { total, kind in
            total + (popularity?.ranking(for: exploreRange, kind: kind)?.totalCount ?? 0)
        }
    }

    /// 探索列表：按关键词、类型、弃用状态筛选，再按下载量或名称排序并截断。
    ///
    /// 默认按下载量排序，只显示范围内下载量最大的若干个包；
    /// 输入搜索关键词时总是返回全部匹配项。
    var filteredCatalog: [BrewCatalogEntry] {
        let query = catalogQuery
        let revision = catalogRevision
        let stamp = popularity?.fetchedAt

        if let cached = exploreResultsCache,
           cached.query == query,
           cached.revision == revision,
           cached.stamp == stamp {
            return cached.result
        }

        let result = query.apply(to: catalog, popularity: popularity)
        exploreResultsCache = (query, revision, stamp, result)
        return result
    }

    /// 缓存筛选结果：一次 body 求值里 `filteredCatalog` 会被读取多次。
    private var exploreResultsCache: (query: BrewCatalogQuery, revision: Int, stamp: Date?, result: [BrewCatalogEntry])?
    /// 目录每次重新载入时递增，用于让筛选缓存失效。
    private var catalogRevision = 0

    /// 当前的探索筛选条件，供界面与测试共用。
    var catalogQuery: BrewCatalogQuery {
        BrewCatalogQuery(
            searchText: exploreSearchText,
            kind: exploreKindFilter,
            range: exploreRange,
            sort: exploreSort,
            limit: exploreLimit,
            showsDeprecated: exploreShowsDeprecated
        )
    }

    /// 探索结果里的 Formula / Cask 数量，用于顶部指标。
    var catalogFormulaCount: Int { catalog.count { $0.kind == .formula } }
    var catalogCaskCount: Int { catalog.count { $0.kind == .cask } }

    func isInstalled(_ entry: BrewCatalogEntry) -> Bool {
        packages.contains { $0.kind == entry.kind && $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }
    }

    /// 已安装的版本。探索列表里显示出来，方便对比最新版本。
    func installedVersion(for entry: BrewCatalogEntry) -> String? {
        packages.first {
            $0.kind == entry.kind && $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }?.installedVersion
    }

    var selectedCatalogEntry: BrewCatalogEntry? {
        guard let selectedCatalogEntryID else { return nil }
        return catalog.first { $0.id == selectedCatalogEntryID }
    }

    func catalogEntry(id: String?) -> BrewCatalogEntry? {
        guard let id else { return nil }
        return catalog.first { $0.id == id }
    }

    /// 当前是否有任何探索筛选条件处于非默认状态。
    var hasActiveExploreFilter: Bool {
        catalogQuery.isActive
    }

    func resetExploreFilters() {
        exploreSearchText = ""
        exploreKindFilter = nil
        exploreSort = .popularity
        exploreLimit = .hundred
        exploreShowsDeprecated = true
    }

    /// 读取 Homebrew 全量目录。
    ///
    /// 与已安装清单分开：这里的数据量更大（约 1.6 万个包），
    /// 只有打开「探索」分区时才会加载，且命中磁盘缓存时不会联网。
    func loadCatalog(force: Bool = false) async {
        guard isAvailable else { return }
        guard !isLoadingCatalog else {
            _ = await catalogTask?.value
            return
        }
        if !force, catalogLoadedRecently {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoadingCatalog = true
            defer {
                self.isLoadingCatalog = false
                self.hasAttemptedCatalogLoad = true
            }

            if let cached = await BrewCatalogService.loadCatalog(force: force) {
                self.catalog = cached.entries
                self.catalogRevision &+= 1
                self.lastCatalogLoadedAt = cached.fetchedAt
                self.hasLoadedCatalog = true
            } else {
                self.errorMessage = L.t("无法读取 Homebrew 目录，请检查网络连接。")
            }
        }

        catalogTask = task
        await task.value
    }

    /// 读取下载量统计。
    func loadPopularity(force: Bool = false) async {
        guard isAvailable else { return }
        guard !isLoadingPopularity else {
            _ = await popularityTask?.value
            return
        }
        if !force, popularityLoadedRecently {
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoadingPopularity = true
            defer {
                self.isLoadingPopularity = false
                self.hasAttemptedPopularityLoad = true
            }

            if let snapshot = await BrewCatalogService.loadPopularity(force: force) {
                self.popularity = snapshot
                self.lastPopularityLoadedAt = snapshot.fetchedAt
            }
        }

        popularityTask = task
        await task.value
    }

    private var catalogLoadedRecently: Bool {
        guard hasLoadedCatalog, let lastCatalogLoadedAt else { return false }
        return Date().timeIntervalSince(lastCatalogLoadedAt) < BrewCatalogService.catalogTTL
    }

    private var popularityLoadedRecently: Bool {
        guard let lastPopularityLoadedAt else { return false }
        return Date().timeIntervalSince(lastPopularityLoadedAt) < BrewCatalogService.popularityTTL
    }

    /// 强制重新下载目录与下载量统计。
    ///
    /// 不清空磁盘缓存：下载失败时仍可退回过期数据，
    /// 用户也可以在设置里单独清除缓存。
    func reloadCatalog() async {
        await loadCatalog(force: true)
        await loadPopularity(force: true)
    }

    /// 跳到「包」分区并选中指定包。
    func revealPackage(_ package: BrewPackage) {
        section = .packages
        searchText = ""
        kindFilter = nil
        showsOutdatedOnly = false
        showsPinnedOnly = false
        showsDependencyPackages = true
        selection = [package.id]
        selectedPackageID = package.id
    }

    /// 跳到「包」分区并选中对应的已安装条目。
    func revealInstalled(_ entry: BrewCatalogEntry) {
        section = .packages
        searchText = entry.name
        kindFilter = nil
        showsOutdatedOnly = false
        showsPinnedOnly = false
        showsDependencyPackages = true

        guard let package = packages.first(where: {
            $0.kind == entry.kind && $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }) else { return }
        selection = [package.id]
        selectedPackageID = package.id
    }

    /// 复制探索条目的安装命令。
    func copyInstallCommand(_ entry: BrewCatalogEntry) {
        BrewExport.copy(entry.installCommand)
    }

    /// 安装探索到的包。安装完成后列表里的「已安装」标记会自动更新。
    func install(_ entry: BrewCatalogEntry) async {
        _ = await runCommand(
            ["install"] + (entry.kind.commandFlag.map { [$0] } ?? []) + [entry.commandName],
            title: L.t("安装 %@", entry.name)
        )
    }

    // MARK: - 加载

    func load(force: Bool = false) async {
        guard !isLoading, !isRunningCommand else { return }
        if !force, let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 15 {
            return
        }
        // 开关关闭或本机未安装 Homebrew 时界面会显示对应状态，无需弹出错误。
        guard isAvailable else { return }

        isLoading = true
        hasAttemptedLoad = true
        defer { isLoading = false }

        if let loaded = await BrewService.loadInventory() {
            inventory = loaded
            lastLoadedAt = Date()
            hasLoaded = true
            let validIDs = Set(loaded.all.map(\.id))
            selection = selection.intersection(validIDs)
            if let selectedPackageID, !validIDs.contains(selectedPackageID) {
                self.selectedPackageID = nil
            }
        } else {
            errorMessage = L.t("无法读取 Homebrew 包列表。")
        }
    }

    // MARK: - 命令执行

    /// 执行一条 brew 命令，并把输出实时写入日志。
    ///
    /// 注意：这里只校验「开关开启 + 已安装」，不校验版本。
    /// 版本过低时仍需要允许执行 `brew update && brew upgrade` 来完成升级。
    @discardableResult
    func runCommand(
        _ arguments: [String],
        title: String,
        refreshAfter: Bool = true
    ) async -> Bool {
        guard isEnabled else {
            errorMessage = L.t("Homebrew 功能已关闭。可在设置中重新开启。")
            return false
        }
        guard isInstalled else {
            errorMessage = L.t("找不到 Homebrew。请确认已经安装 Homebrew。")
            return false
        }
        guard !isRunningCommand else {
            appendLog(.info, L.t("已有命令正在执行，请稍候。"))
            return false
        }

        let commandLine = (["brew"] + arguments).joined(separator: " ")
        isRunningCommand = true
        appendLog(.command, "$ " + commandLine)

        let started = Date()
        let session = BrewService.start(arguments: arguments)
        runningProcess = session.handle

        var buffer = ""
        var pendingLines: [String] = []

        // 将输出按行聚合，避免每条 chunk 都触发一次 UI 刷新。
        func flushBuffer(force: Bool = false) {
            while let index = buffer.firstIndex(of: "\n") {
                let line = String(buffer[buffer.startIndex..<index])
                buffer.removeSubrange(buffer.startIndex...index)
                pendingLines.append(line)
            }
            if force, !buffer.isEmpty {
                pendingLines.append(buffer)
                buffer.removeAll()
            }
            guard !pendingLines.isEmpty else { return }
            let text = pendingLines.joined(separator: "\n")
            pendingLines.removeAll()
            if !text.isEmpty {
                appendLog(.output, text)
            }
        }

        var result = BrewCommandResult(exitCode: -1, wasCancelled: false)
        for await event in session.stream {
            switch event {
            case .output(let chunk):
                buffer += chunk
                flushBuffer()
            case .finished(let finished):
                result = finished
                flushBuffer(force: true)
            }
        }

        runningProcess = nil
        let duration = Date().timeIntervalSince(started)

        if result.wasCancelled {
            appendLog(.failure, L.t("命令已取消（%.1f 秒）", duration))
        } else if result.succeeded {
            appendLog(.success, L.t("命令完成（%.1f 秒）", duration))
        } else {
            appendLog(.failure, L.t("命令失败，退出码 %d（%.1f 秒）", Int(result.exitCode), duration))
        }

        history.insert(BrewCommandHistoryItem(
            title: title,
            commandLine: commandLine,
            arguments: arguments,
            succeeded: result.succeeded,
            date: Date(),
            duration: duration
        ), at: 0)
        if history.count > 50 {
            history.removeLast(history.count - 50)
        }

        isRunningCommand = false

        if refreshAfter {
            await load(force: true)
        }

        return result.succeeded
    }

    func cancelRunningCommand() {
        runningProcess?.cancel()
        appendLog(.info, L.t("正在停止命令…"))
    }

    /// 关闭开关时停止正在执行的命令并清空运行时状态。
    /// Homebrew 快照与日志保留，方便重新开启后继续使用。
    private func deactivate() {
        runningProcess?.cancel()
        runningProcess = nil
        inventory = nil
        hasLoaded = false
        hasAttemptedLoad = false
        lastLoadedAt = nil
        selection.removeAll()
        selectedPackageID = nil

        // 探索目录是网络数据，与 Homebrew 开关状态保持一致：关闭后不保留。
        catalog = []
        catalogRevision &+= 1
        hasLoadedCatalog = false
        hasAttemptedCatalogLoad = false
        lastCatalogLoadedAt = nil
        popularity = nil
        lastPopularityLoadedAt = nil
        hasAttemptedPopularityLoad = false
        exploreResultsCache = nil
        selectedCatalogEntryID = nil

        appendLog(.info, L.t("Homebrew 功能已关闭，不再执行任何 brew 命令。"))
    }

    /// 重新检测本机是否安装了 Homebrew，并刷新版本。
    func rediscover() {
        executableURL = BrewService.locateExecutable()
        detectedVersion = Self.detectVersionSynchronously()
        guard isAvailable else { return }
        Task { await load(force: true) }
    }

    func clearLog() {
        logEntries.removeAll()
    }

    func rerun(_ item: BrewCommandHistoryItem) {
        Task {
            await runCommand(item.arguments, title: item.title)
        }
    }

    private func appendLog(_ level: BrewLogEntry.Level, _ text: String) {
        logEntries.append(BrewLogEntry(level: level, text: text))
        if logEntries.count > 2000 {
            logEntries.removeFirst(logEntries.count - 2000)
        }
    }

    // MARK: - 包操作

    func install(_ names: [String], kind: BrewPackageKind) async {
        guard !names.isEmpty else { return }
        _ = await runCommand(
            ["install"] + (kind.commandFlag.map { [$0] } ?? []) + names,
            title: L.t("安装 %@", names.joined(separator: ", "))
        )
    }

    func uninstall(_ packages: [BrewPackage]) async {
        let formulae = packages.filter { $0.kind == .formula }.map(\.commandName)
        let casks = packages.filter { $0.kind == .cask }.map(\.commandName)

        if !formulae.isEmpty {
            _ = await runCommand(
                ["uninstall"] + formulae,
                title: L.t("卸载 %@", formulae.joined(separator: ", "))
            )
        }
        if !casks.isEmpty {
            _ = await runCommand(
                ["uninstall", "--cask"] + casks,
                title: L.t("卸载 %@", casks.joined(separator: ", "))
            )
        }
    }

    func upgrade(_ packages: [BrewPackage]) async {
        guard !packages.isEmpty else { return }
        let names = packages.map(\.commandName)

        // 传进来的包都已经由当前策略判定为可更新（`brew info` 与界面用同一套环境变量），
        // 因此这里只需要在贪婪模式下补上 `--greedy`，保证命令与列表一致。
        _ = await runCommand(
            ["upgrade"] + upgradePolicy.arguments(for: "upgrade") + names,
            title: L.t("升级 %@", names.joined(separator: ", "))
        )
    }

    func upgradeAll() async {
        _ = await runCommand(
            ["upgrade"] + upgradePolicy.arguments(for: "upgrade"),
            title: L.t("升级全部可更新包")
        )
    }

    func reinstall(_ package: BrewPackage) async {
        _ = await runCommand(
            ["reinstall"] + (package.kind == .cask ? ["--cask"] : []) + [package.commandName],
            title: L.t("重新安装 %@", package.name)
        )
    }

    func pin(_ package: BrewPackage) async {
        _ = await runCommand(
            ["pin"] + (package.kind == .cask ? ["--cask"] : []) + [package.commandName],
            title: L.t("固定 %@", package.name)
        )
    }

    func unpin(_ package: BrewPackage) async {
        _ = await runCommand(
            ["unpin"] + (package.kind == .cask ? ["--cask"] : []) + [package.commandName],
            title: L.t("取消固定 %@", package.name)
        )
    }

    func run(_ title: String, arguments: [String]) async {
        _ = await runCommand(arguments, title: title)
    }

    // MARK: - 快照

    func loadSnapshots() {
        do {
            snapshots = try snapshotRepository.load().sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = L.t("无法读取 Homebrew 快照：%@", error.localizedDescription)
        }
    }

    /// 保存 Homebrew 快照。若当前清单尚未加载会先读取。
    func saveSnapshot() async {
        guard isAvailable else {
            errorMessage = L.t("Homebrew 功能当前不可用，无法保存快照。")
            return
        }
        guard !isSavingSnapshot else { return }

        if inventory == nil {
            await load(force: true)
        }
        guard let inventory else {
            errorMessage = L.t("当前没有可保存的 Homebrew 包列表。")
            return
        }

        isSavingSnapshot = true
        defer { isSavingSnapshot = false }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let snapshot = BrewSnapshot(
            name: formatter.string(from: Date()),
            brewVersion: inventory.brewVersion,
            prefix: inventory.prefix,
            formulae: inventory.formulae,
            casks: inventory.casks
        )

        do {
            try snapshotRepository.save(snapshot)
            snapshots.insert(snapshot, at: 0)
        } catch {
            errorMessage = L.t("无法保存 Homebrew 快照：%@", error.localizedDescription)
        }
    }

    func deleteSnapshot(id: UUID) {
        do {
            try snapshotRepository.delete(id: id)
            snapshots.removeAll { $0.id == id }
        } catch {
            errorMessage = L.t("无法删除 Homebrew 快照：%@", error.localizedDescription)
        }
    }

    func renameSnapshot(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        var updated = snapshots[index]
        updated.name = trimmed
        do {
            try snapshotRepository.save(updated)
            snapshots[index] = updated
        } catch {
            errorMessage = L.t("无法保存 Homebrew 快照：%@", error.localizedDescription)
        }
    }

    func updateSnapshotNote(id: UUID, note: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        var updated = snapshots[index]
        updated.note = note
        do {
            try snapshotRepository.save(updated)
            snapshots[index] = updated
        } catch {
            errorMessage = L.t("无法保存 Homebrew 快照：%@", error.localizedDescription)
        }
    }

    // MARK: - 导出

    /// 导出当前已安装包为 Brewfile。
    func exportCurrentBrewfile() {
        guard let inventory else {
            errorMessage = L.t("Homebrew 清单尚未加载。")
            return
        }
        let text = BrewfileBuilder.text(
            formulae: inventory.formulae.map(\.commandName),
            casks: inventory.casks.map(\.commandName),
            header: L.t("由 Custocub 生成 · %@", Date().formatted(date: .abbreviated, time: .shortened))
        )
        BrewExport.save(
            text: text,
            suggestedName: "Brewfile",
            contentType: .brewfile
        )
    }

    func exportSnapshotBrewfile(_ snapshot: BrewSnapshot) {
        let text = BrewfileBuilder.text(
            formulae: snapshot.formulaNames,
            casks: snapshot.caskTokens,
            header: L.t("Custocub Homebrew 快照 · %@", snapshot.name)
        )
        BrewExport.save(
            text: text,
            suggestedName: "Brewfile-\(snapshot.name)",
            contentType: .brewfile
        )
    }

    /// 只导出 Formula 部分，便于单独备份命令行工具。
    func exportSnapshotFormulae(_ snapshot: BrewSnapshot) {
        let text = BrewfileBuilder.text(
            formulae: snapshot.formulaNames,
            casks: [],
            header: L.t("Custocub Homebrew 快照 · %@ · Formula", snapshot.name)
        )
        BrewExport.save(
            text: text,
            suggestedName: "Brewfile-Formula-\(snapshot.name)",
            contentType: .brewfile
        )
    }

    /// 只导出 Cask 部分，作为一份独立的应用列表。
    func exportSnapshotCasks(_ snapshot: BrewSnapshot) {
        let text = BrewfileBuilder.text(
            formulae: [],
            casks: snapshot.caskTokens,
            header: L.t("Custocub Homebrew 快照 · %@ · Cask", snapshot.name)
        )
        BrewExport.save(
            text: text,
            suggestedName: "Brewfile-Cask-\(snapshot.name)",
            contentType: .brewfile
        )
    }

    func exportCurrentFormulae() {
        guard let inventory else { return }
        let text = BrewfileBuilder.text(
            formulae: inventory.formulae.map(\.commandName),
            casks: [],
            header: L.t("由 Custocub 生成 · %@ · Formula", Date().formatted(date: .abbreviated, time: .shortened))
        )
        BrewExport.save(text: text, suggestedName: "Brewfile-Formula", contentType: .brewfile)
    }

    func exportCurrentCasks() {
        guard let inventory else { return }
        let text = BrewfileBuilder.text(
            formulae: [],
            casks: inventory.casks.map(\.commandName),
            header: L.t("由 Custocub 生成 · %@ · Cask", Date().formatted(date: .abbreviated, time: .shortened))
        )
        BrewExport.save(text: text, suggestedName: "Brewfile-Cask", contentType: .brewfile)
    }

    func exportSnapshotInstallScript(_ snapshot: BrewSnapshot) {
        let commands = BrewfileBuilder.installCommands(
            formulae: snapshot.formulaNames,
            casks: snapshot.caskTokens
        )
        BrewExport.save(
            text: "#!/bin/bash\n" + commands + "\n",
            suggestedName: "install-\(snapshot.name).sh",
            contentType: .shellScript
        )
    }

    func copyInstallCommand(_ package: BrewPackage) {
        BrewExport.copy(package.installCommand)
    }

    // MARK: - 维护命令

    /// 更新 Homebrew 索引。升级完成后会重新检测版本，
    /// 以便版本过低时界面能自动解除限制。
    func updateIndex() async {
        await runCommand(["update"], title: L.t("更新 Homebrew 索引"))

        // 升级可能已把 Homebrew 更新到受支持的版本。
        let output = await BrewService.runQuiet(arguments: ["--version"]).output
        if let latest = BrewVersion(output: output) {
            detectedVersion = latest
            if latest.isSupported && isAvailable {
                await load(force: true)
            }
        }
    }

    // MARK: - 清理

    /// 分析可清理的内容。只执行只读命令，不修改任何文件。
    func analyzeCleanup(force: Bool = false) async {
        guard isAvailable, !isAnalyzingCleanup else { return }
        if !force, let lastCleanupAnalyzedAt,
           Date().timeIntervalSince(lastCleanupAnalyzedAt) < 60 {
            return
        }

        isAnalyzingCleanup = true
        defer { isAnalyzingCleanup = false }

        cleanupReport = await BrewCleanupService.analyze()
        lastCleanupAnalyzedAt = Date()
    }

    /// 标准清理：等价于 `brew cleanup`。
    /// 移除过期下载、旧版本 keg、残留锁文件和日志。
    /// 无用依赖需要单独运行 autoremove。
    func cleanupStandard() async {
        await runCleanup(["cleanup"], title: L.t("清理缓存与旧版本"))
    }

    /// 深度清理：等价于 `brew cleanup --prune=all`。
    /// 删除所有缓存下载（包括最新版本），能释放最多空间。
    func cleanupAll() async {
        await runCleanup(["cleanup", "--prune=all"], title: L.t("清理全部缓存"))
    }

    /// 彻底清空下载缓存目录，等价于删除 `$(brew --cache)`。
    /// 下次安装或升级时会重新下载。
    func cleanupEverything() async {
        await runCleanup(["cleanup", "--prune=all", "--scrub"], title: L.t("清空下载缓存"))
    }

    /// 执行清理命令，并在成功后用清理前后可释放空间的差值
    /// 估算实际释放量。失败或被取消时不再显示上一次的估算值。
    private func runCleanup(_ arguments: [String], title: String) async {
        let before = cleanupReport?.estimatedFreeBytes
        let succeeded = await runCommand(arguments, title: title)
        await analyzeCleanup(force: true)

        guard succeeded else {
            lastCleanupFreedBytes = nil
            return
        }
        guard let before else { return }
        lastCleanupFreedBytes = max(0, before - (cleanupReport?.estimatedFreeBytes ?? 0))
    }

    /// 试运行清理，只显示会删除什么。
    func cleanupDryRun() async {
        await runCommand(["cleanup", "-n"], title: L.t("预览清理内容"), refreshAfter: false)
    }

    /// 只清理某个包的旧版本。
    func cleanupPackage(_ package: BrewPackage) async {
        await runCommand(
            ["cleanup", package.commandName],
            title: L.t("清理 %@ 的旧版本", package.name)
        )
        await analyzeCleanup(force: true)
    }

    /// 移除不再被需要的依赖。Homebrew 会保留仍被其他包依赖的 formula。
    func autoremove() async {
        await runCommand(["autoremove"], title: L.t("移除不再需要的依赖"))
        await analyzeCleanup(force: true)
    }

    /// 试运行 autoremove，只看会移除哪些包。
    func autoremoveDryRun() async {
        await runCommand(["autoremove", "-n"], title: L.t("预览无用依赖"), refreshAfter: false)
    }

    /// 检查已安装包的依赖是否完整。
    func checkMissing() async {
        await runCommand(["missing"], title: L.t("检查缺失依赖"), refreshAfter: false)
    }

    /// 清理残留的锁文件。
    func cleanupLockfiles() async {
        await runCommand(["cleanup", "-s"], title: L.t("清理残留锁文件"))
        await analyzeCleanup(force: true)
    }

    /// 修复安装前缀里的符号链接和空目录，等价于 `brew cleanup --prune-prefix`。
    func prunePrefix() async {
        await runCommand(["cleanup", "--prune-prefix"], title: L.t("修复安装前缀链接"), refreshAfter: false)
    }

    // MARK: - 后台服务

    /// 读取 `brew services` 的服务列表。
    ///
    /// 使用独立任务：切换分区时 SwiftUI 会取消 `.task`，
    /// 跟随视图生命周期会导致读取被中断、列表为空。
    func loadServices(force: Bool = false) async {
        guard isAvailable else { return }
        if !force, let lastServicesLoadedAt,
           Date().timeIntervalSince(lastServicesLoadedAt) < 10 {
            return
        }
        if isLoadingServices {
            _ = await servicesTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoadingServices = true
            defer { self.isLoadingServices = false }

            if let entries = await BrewServicesService.load() {
                self.serviceEntries = entries
                self.lastServicesLoadedAt = Date()
            } else {
                self.errorMessage = L.t("无法读取 brew services 的服务列表。")
            }
        }

        servicesTask = task
        await task.value
    }

    /// 启动服务，并注册为登录（或开机）自动启动，等价于 `brew services start`。
    func startService(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["start", service.name],
            title: L.t("启动服务 %@", service.name)
        )
    }

    /// 停止服务并取消自动启动注册，等价于 `brew services stop`。
    func stopService(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["stop", service.name],
            title: L.t("停止服务 %@", service.name)
        )
    }

    /// 重启服务，等价于 `brew services restart`。
    func restartService(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["restart", service.name],
            title: L.t("重启服务 %@", service.name)
        )
    }

    /// 只运行一次、不注册自动启动，等价于 `brew services run`。
    func runServiceOnce(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["run", service.name],
            title: L.t("运行服务 %@（不自动启动）", service.name)
        )
    }

    /// 立即停止但保留注册，等价于 `brew services kill`。
    func killService(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["kill", service.name],
            title: L.t("立即停止服务 %@", service.name)
        )
    }

    /// 停止时保留自动启动注册，等价于 `brew services stop --keep`。
    func stopServiceKeepingRegistration(_ service: BrewServiceInfo) async {
        await runServicesCommand(
            ["stop", "--keep", service.name],
            title: L.t("停止服务 %@（保留自动启动）", service.name)
        )
    }

    /// 启动全部已注册的服务，等价于 `brew services start --all`。
    func startAllServices() async {
        await runServicesCommand(["start", "--all"], title: L.t("启动全部服务"))
    }

    /// 停止全部已注册的服务，等价于 `brew services stop --all`。
    func stopAllServices() async {
        await runServicesCommand(["stop", "--all"], title: L.t("停止全部服务"))
    }

    /// 清理无用服务，等价于 `brew services cleanup`。
    func cleanupServices() async {
        await runServicesCommand(["cleanup"], title: L.t("清理无用服务"))
    }

    private func runServicesCommand(_ arguments: [String], title: String) async {
        await runCommand(["services"] + arguments, title: title, refreshAfter: false)
        await loadServices(force: true)
    }

    // MARK: - 配置与诊断

    /// 读取 `brew config`。
    ///
    /// 同样使用独立任务，避免切换分区时被取消而留下空配置。
    func loadConfig(force: Bool = false) async {
        guard isAvailable else { return }
        if !force, configInfo != nil { return }
        if isLoadingConfig {
            _ = await configTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoadingConfig = true
            defer { self.isLoadingConfig = false }
            self.configInfo = await BrewHealthService.loadConfig()
        }

        configTask = task
        await task.value
    }

    /// 运行 `brew doctor` 并把结果结构化展示；同时写入命令日志。
    ///
    /// 使用独立的 unstructured 任务执行：SwiftUI 切换分区时 `.task` 会被取消，
    /// 若跟随视图生命周期，命令会被中途打断并留下不完整的结果。
    func runDoctor(force: Bool = false) async {
        guard isAvailable else { return }
        if !force, doctorReport != nil { return }
        if isRunningDoctor {
            // 已有检查在跑，等它结束即可。
            _ = await doctorTask?.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRunningDoctor = true
            defer { self.isRunningDoctor = false }

            self.logEntries.append(BrewLogEntry(level: .command, text: "$ brew doctor --json"))
            let started = Date()

            let report = await BrewHealthService.loadDoctor()
            self.doctorReport = report

            let duration = Date().timeIntervalSince(started)
            guard let report else {
                self.logEntries.append(BrewLogEntry(
                    level: .failure,
                    text: L.t("无法读取 brew doctor 输出（%.1f 秒）", duration)
                ))
                return
            }

            if !report.isComplete {
                self.logEntries.append(BrewLogEntry(
                    level: .failure,
                    text: L.t("诊断输出不完整（%.1f 秒）", duration)
                ))
            } else if report.isHealthy {
                self.logEntries.append(BrewLogEntry(
                    level: .success,
                    text: L.t("未发现问题（%.1f 秒）", duration)
                ))
            } else {
                self.logEntries.append(BrewLogEntry(
                    level: .failure,
                    text: L.t("发现 %d 个问题（%.1f 秒）", report.findings.count, duration)
                ))
            }
        }

        doctorTask = task
        await task.value
    }

    func showOutdated() async {
        _ = await runCommand(
            ["outdated", "--verbose"] + upgradePolicy.arguments(for: "outdated"),
            title: L.t("查看可更新的包"),
            refreshAfter: false
        )
    }
}

/// 判断使用哪种导出文件类型。
enum BrewExportContentType {
    case brewfile
    case shellScript
    case plainText
}

/// 简单的文本导出/复制辅助。
@MainActor
enum BrewExport {
    static func save(text: String, suggestedName: String, contentType: BrewExportContentType) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true

        switch contentType {
        case .brewfile:
            // Brewfile 通常没有扩展名，因此不限制文件类型，避免系统自动追加后缀。
            panel.nameFieldStringValue = suggestedName
        case .shellScript:
            panel.nameFieldStringValue = suggestedName.hasSuffix(".sh") ? suggestedName : suggestedName + ".sh"
            panel.allowedContentTypes = [.shellScript]
        case .plainText:
            panel.nameFieldStringValue = suggestedName
            panel.allowedContentTypes = [.plainText]
        }

        panel.message = L.t("导出后可交给 homebrew-bundle 或直接执行")
        panel.prompt = L.t("导出")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
