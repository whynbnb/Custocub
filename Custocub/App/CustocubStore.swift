import AppKit
import Foundation

enum SidebarSelection: Hashable {
    case installed
    case newlyInstalled
    case updated
    case uninstalled
    case own
    case gallery
    case favorites
    case collection(UUID)
    case brew
    case source(AppSource?)
    case snapshot(UUID)
}

enum AppTypeFilter: String, CaseIterable, Identifiable {
    case all
    case system
    case thirdParty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L.t("全部类型")
        case .system: L.t("系统应用")
        case .thirdParty: L.t("第三方应用")
        }
    }

    func matches(_ app: AppRecord) -> Bool {
        switch self {
        case .all: true
        case .system: app.isSystemApp
        case .thirdParty: !app.isSystemApp
        }
    }
}

struct SelectedAppContext {
    let app: AppRecord
    let galleryItem: GalleryItem?
    let snapshot: AppSnapshot?
    /// 「已更新」列表里，这个应用在最近快照中的旧版本号。
    var previousVersion: String? = nil
}

/// 侧边栏计数缓存：启动时先用上一次扫描的结果完整显示，
/// 等新扫描完成后再替换为实时数据。
private struct SidebarCache: Codable {
    var installedCount: Int
    var ownAppCount: Int
    var ownManualCount: Int?
    var galleryCount: Int
    var uninstalledCount: Int
    var sourceCounts: [String: Int]
    var lastScanAt: Date
}

@MainActor
final class CustocubStore: ObservableObject {
    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var snapshots: [AppSnapshot] = [] {
        didSet {
            iconHistoryCache.removeAll()
            if let id = gallerySnapshotID, !snapshots.contains(where: { $0.id == id }) {
                gallerySnapshotID = nil
            }
        }
    }
    /// 图标历史按应用缓存；快照列表变化时清空。
    private var iconHistoryCache: [String: [AppIconHistoryEntry]] = [:]
    @Published var sidebarSelection: SidebarSelection? = .installed
    @Published var selectedAppID: String?

    @Published private(set) var isScanning = false
    @Published private(set) var isEnriching = false
    @Published private(set) var isSavingSnapshot = false
    @Published private(set) var enrichmentDone = 0
    @Published private(set) var enrichmentTotal = 0
    @Published private(set) var lastScanAt: Date?
    @Published private(set) var hasScanned = false

    @Published var errorMessage: String?
    @Published var statusMessage = ""

    @Published var searchText = ""
    @Published var sourceFilter: AppSource?
    @Published var platformFilter: AppPlatform?
    @Published var typeFilter: AppTypeFilter = .all
    /// 展示框专用筛选，支持多选。空集合表示「全部」。
    @Published var gallerySourceFilters: Set<AppSource> = []
    @Published var galleryPlatformFilters: Set<AppPlatform> = []
    @Published var galleryTypeFilters: Set<AppTypeFilter> = []
    @Published var galleryStatusFilters: Set<GalleryItem.Status> = []
    /// 展示框时间机器：nil 表示今天，否则查看指定历史快照。
    @Published var gallerySnapshotID: UUID?
    @Published private(set) var collections: [AppCollection] = []
    @Published private(set) var favoriteKeys: Set<String> = []

    private let repository: SnapshotRepository
    private let scanner: AppScanner
    private var sizeCache: SizeCache
    private var enrichmentTask: Task<Void, Never>?
    private var iconPrefetchTask: Task<Void, Never>?
    private var enrichmentToken = UUID()
    private let liveSnapshotID = UUID()
    private var cachedSidebar: SidebarCache?

    private static let sidebarCacheKey = "sidebarCache.v2"

    init(
        repository: SnapshotRepository = SnapshotRepository(),
        scanner: AppScanner = AppScanner(),
        sizeCache: SizeCache = SizeCache.load()
    ) {
        self.repository = repository
        self.scanner = scanner
        self.sizeCache = sizeCache
        loadSnapshots()
        loadSidebarCache()
        loadCollections()
    }


    // MARK: - Derived data

    var activeSelection: SidebarSelection {
        sidebarSelection ?? .installed
    }

    /// 扫描完成前使用上一次的侧边栏计数，避免列表逐步刷新。
    private var usesCachedSidebar: Bool {
        !hasScanned && cachedSidebar != nil
    }

    var installedCount: Int {
        if usesCachedSidebar, let cachedSidebar { return cachedSidebar.installedCount }
        return apps.count
    }
    var systemCount: Int { apps.count { $0.isSystemApp } }
    var thirdPartyCount: Int { apps.count { !$0.isSystemApp } }
    var ownAppCount: Int {
        if usesCachedSidebar, let cachedSidebar { return cachedSidebar.ownAppCount }
        return apps.count { $0.isOwn }
    }

    /// 开发者的应用计入来源统计的数量：只统计仍然属于「手动安装」的项，
    /// Homebrew、App Store 等真实来源优先，避免重复计数。
    var ownManualCount: Int {
        if usesCachedSidebar, let cachedSidebar {
            return cachedSidebar.ownManualCount ?? cachedSidebar.ownAppCount
        }
        return apps.count { $0.isOwn && $0.source == .manual }
    }

    /// 当前浏览的来源分类中，某个应用是否是额外插入的管理工具节点。
    func isManagerNode(_ app: AppRecord) -> Bool {
        guard let managerSource = app.managerSource else { return false }
        return sourceFilter == managerSource && app.source != managerSource
    }

    /// 侧边栏「展示框」计数；扫描前使用缓存值。
    var sidebarGalleryCount: Int {
        if usesCachedSidebar, let cachedSidebar { return cachedSidebar.galleryCount }
        return galleryItems.count
    }

    var ownTotalSize: Int64 {
        apps.filter(\.isOwn).compactMap(\.sizeInBytes).reduce(0, +)
    }

    var ownTotalSizeText: String {
        if apps.contains(where: { $0.isOwn && $0.sizeInBytes == nil }) {
            return L.t("计算中…")
        }
        return ownTotalSize.formatted(.byteCount(style: .file))
    }

    var sourceCounts: [AppSource: Int] {
        if usesCachedSidebar, let cachedSidebar {
            var counts: [AppSource: Int] = [:]
            for (rawValue, count) in cachedSidebar.sourceCounts {
                if let source = AppSource(rawValue: rawValue) {
                    counts[source] = count
                }
            }
            return counts
        }
        var counts = Dictionary(grouping: apps, by: \.source).mapValues(\.count)
        // 开发者的应用从「手动安装」中分离，单独归入「开发者的应用」。
        counts[.manual] = apps.count { $0.source == .manual && !$0.isOwn }
        return counts
    }

    var totalSize: Int64 {
        apps.compactMap(\.sizeInBytes).reduce(0, +)
    }

    var totalSizeText: String {
        if apps.contains(where: { $0.sizeInBytes == nil }) {
            return L.t("计算中…")
        }
        return totalSize.formatted(.byteCount(style: .file))
    }

    var liveSnapshot: AppSnapshot? {
        guard hasScanned else { return nil }
        return AppSnapshot(
            id: liveSnapshotID,
            name: L.t("当前状态"),
            createdAt: lastScanAt ?? Date(),
            apps: apps
        )
    }

    var comparisonSnapshots: [AppSnapshot] {
        var result: [AppSnapshot] = []
        if let liveSnapshot { result.append(liveSnapshot) }
        result.append(contentsOf: snapshots)
        return result
    }

    var selectedSnapshot: AppSnapshot? {
        guard case .snapshot(let id) = activeSelection else { return nil }
        return snapshots.first { $0.id == id }
    }

    var selectedAppContext: SelectedAppContext? {
        guard let selectedAppID else { return nil }

        switch activeSelection {
        case .installed, .own, .source:
            guard let app = apps.first(where: { $0.id == selectedAppID }) else { return nil }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: nil)

        case .newlyInstalled:
            guard let app = newlyInstalledApps.first(where: { $0.id == selectedAppID }) else { return nil }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: nil)

        case .updated:
            guard let app = updatedApps.first(where: { $0.id == selectedAppID }) else { return nil }
            let oldVersion = latestSnapshot?.apps.first { comparisonKey(for: $0) == comparisonKey(for: app) }?.version
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: nil, previousVersion: oldVersion)

        case .uninstalled:
            guard let snapshot = latestSnapshot,
                  let app = snapshot.apps.first(where: { $0.id == selectedAppID }) else { return nil }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: snapshot)

        case .brew:
            return nil

        case .gallery, .favorites, .collection:
            if let item = galleryDisplayItems.first(where: { $0.app.id == selectedAppID }) {
                return SelectedAppContext(app: item.app, galleryItem: item, snapshot: nil)
            }
            guard gallerySnapshot == nil,
                  let app = apps.first(where: { $0.id == selectedAppID }) else { return nil }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: nil)

        case .snapshot(let id):
            guard let snapshot = snapshots.first(where: { $0.id == id }),
                  let app = snapshot.apps.first(where: { $0.id == selectedAppID }) else {
                return nil
            }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: snapshot)
        }
    }

    /// 实时应用 + 历史快照中出现过、但当前已不存在的应用。
    var galleryItems: [GalleryItem] {
        var items: [GalleryItem] = []
        var installedBundleIDs = Set<String>()
        var installedPaths = Set<String>()

        for app in apps {
            installedPaths.insert(app.path)
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                installedBundleIDs.insert(bundleID)
            }
            items.append(GalleryItem(
                id: app.path,
                app: app,
                status: .installed,
                lastSeenAt: lastScanAt,
                snapshotName: nil
            ))
        }

        var seenHistoricalKeys = Set<String>()

        for snapshot in snapshots {
            for app in snapshot.apps {
                if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                    guard !installedBundleIDs.contains(bundleID) else { continue }
                } else {
                    guard !installedPaths.contains(app.path) else { continue }
                }
                guard !installedPaths.contains(app.path) else { continue }

                let key = app.bundleIdentifier?.isEmpty == false ? app.bundleIdentifier! : app.path
                guard seenHistoricalKeys.insert(key).inserted else { continue }

                items.append(GalleryItem(
                    id: app.path,
                    app: app,
                    status: .uninstalled,
                    lastSeenAt: snapshot.createdAt,
                    snapshotName: snapshot.name
                ))
            }
        }

        return items.sorted {
            if $0.status != $1.status {
                return $0.status == .installed
            }
            return $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
        }
    }

    /// 时间机器当前选中的历史快照。
    var gallerySnapshot: AppSnapshot? {
        guard let gallerySnapshotID else { return nil }
        return snapshots.first { $0.id == gallerySnapshotID }
    }

    /// 展示框实际显示的内容：今天或某个历史快照。
    var galleryDisplayItems: [GalleryItem] {
        guard let snapshot = gallerySnapshot else { return galleryItems }

        let liveKeys = Set(apps.map { comparisonKey(for: $0) })
        return snapshot.apps.map { app in
            GalleryItem(
                id: app.path,
                app: app,
                status: liveKeys.contains(comparisonKey(for: app)) ? .installed : .uninstalled,
                lastSeenAt: snapshot.createdAt,
                snapshotName: snapshot.name
            )
        }
        .sorted {
            if $0.status != $1.status {
                return $0.status == .installed
            }
            return $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
        }
    }

    /// 展示框当前作用域内的应用：展示框、收藏或某个合集。
    var galleryScopedItems: [GalleryItem] {
        switch activeSelection {
        case .favorites:
            return galleryDisplayItems.filter { isFavorite($0.app) }
        case .collection(let id):
            guard let collection = collection(id) else { return [] }
            return galleryDisplayItems.filter {
                collection.appKeys.contains(collectionKey(for: $0.app))
            }
        default:
            return galleryDisplayItems
        }
    }

    var isGalleryFavorites: Bool {
        if case .favorites = activeSelection { return true }
        return false
    }

    var galleryActiveCollection: AppCollection? {
        guard case .collection(let id) = activeSelection else { return nil }
        return collection(id)
    }

    var galleryScopeTitle: String {
        if isGalleryFavorites { return L.t("收藏") }
        if let collection = galleryActiveCollection { return collection.name }
        return L.t("展示框")
    }

    var galleryScopeHelp: String {
        if isGalleryFavorites { return L.t("收藏的应用") }
        if galleryActiveCollection != nil { return L.t("自定义合集") }
        return L.t("像收藏柜一样浏览所有软件，包括已经卸载、但仍保存在历史快照中的应用。")
    }

    // MARK: - 收藏与合集

    func collectionKey(for app: AppRecord) -> String {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }
        return app.path
    }

    func isFavorite(_ app: AppRecord) -> Bool {
        favoriteKeys.contains(collectionKey(for: app))
    }

    func toggleFavorite(_ app: AppRecord) {
        let key = collectionKey(for: app)
        if favoriteKeys.contains(key) {
            favoriteKeys.remove(key)
        } else {
            favoriteKeys.insert(key)
        }
        saveCollections()
    }

    var favoriteCount: Int { favoriteKeys.count }

    @discardableResult
    func createCollection(named name: String, containing app: AppRecord? = nil) -> UUID {
        var trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = L.t("新合集")
        }

        var collection = AppCollection(name: trimmed)
        if let app {
            collection.appKeys.insert(collectionKey(for: app))
        }
        collections.append(collection)
        saveCollections()
        return collection.id
    }

    func renameCollection(id: UUID, name: String) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        collections[index].name = trimmed
        saveCollections()
    }

    func deleteCollection(id: UUID) {
        collections.removeAll { $0.id == id }
        if case .collection(let selectedID) = activeSelection, selectedID == id {
            sidebarSelection = .gallery
            selectedAppID = nil
        }
        saveCollections()
    }

    func add(_ app: AppRecord, toCollection id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].appKeys.insert(collectionKey(for: app))
        saveCollections()
    }

    func remove(_ app: AppRecord, fromCollection id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].appKeys.remove(collectionKey(for: app))
        saveCollections()
    }

    func collection(_ id: UUID) -> AppCollection? {
        collections.first { $0.id == id }
    }

    func isInCollection(_ app: AppRecord, collectionID: UUID) -> Bool {
        guard let collection = collection(collectionID) else { return false }
        return collection.appKeys.contains(collectionKey(for: app))
    }

    func collectionItems(_ collection: AppCollection, from items: [GalleryItem]) -> [GalleryItem] {
        items.filter { collection.appKeys.contains(collectionKey(for: $0.app)) }
    }

    private static var collectionsFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent("collections.json")
    }

    private struct CollectionsDocument: Codable {
        var favorites: Set<String> = []
        var collections: [AppCollection] = []
    }

    private func loadCollections() {
        guard let data = try? Data(contentsOf: Self.collectionsFileURL),
              let document = try? JSONDecoder().decode(CollectionsDocument.self, from: data) else {
            return
        }
        favoriteKeys = document.favorites
        collections = document.collections
    }

    private func saveCollections() {
        do {
            let url = Self.collectionsFileURL
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let document = CollectionsDocument(favorites: favoriteKeys, collections: collections)
            let data = try JSONEncoder().encode(document)
            try data.write(to: url, options: .atomic)
        } catch {
            // 收藏数据写入失败不应影响浏览。
        }
    }

    var uninstalledCount: Int {
        if usesCachedSidebar, let cachedSidebar { return cachedSidebar.uninstalledCount }
        guard hasScanned else { return 0 }
        return galleryItems.count { $0.status == .uninstalled }
    }

    // MARK: - 与最近快照对比

    /// 最近一次保存的快照。「已更新」「已卸载」都以它为基准。
    var latestSnapshot: AppSnapshot? {
        snapshots.first
    }

    /// 跨快照匹配同一个应用：优先 Bundle ID，其次路径。
    private func comparisonKey(for app: AppRecord) -> String {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return "id:\(bundleID)"
        }
        return "path:\(app.path)"
    }

    /// 最近快照之后新安装的应用：当前有、快照里没有。
    var newlyInstalledApps: [AppRecord] {
        guard hasScanned, let snapshot = latestSnapshot else { return [] }
        let snapshotKeys = Set(snapshot.apps.map { comparisonKey(for: $0) })
        return apps.filter { !snapshotKeys.contains(comparisonKey(for: $0)) }
    }

    /// 最近快照里记录过、版本已经变化、且当前仍在的应用。
    var updatedApps: [AppRecord] {
        guard hasScanned, let snapshot = latestSnapshot else { return [] }
        var previous: [String: AppRecord] = [:]
        for app in snapshot.apps {
            previous[comparisonKey(for: app)] = app
        }
        return apps.filter { app in
            guard let old = previous[comparisonKey(for: app)] else { return false }
            return Self.versionChanged(from: old, to: app)
        }
    }

    /// 从历史快照中提取图标变化；连续相同的图标只保留第一次出现的快照。
    func iconHistory(for app: AppRecord) -> [AppIconHistoryEntry] {
        let key = comparisonKey(for: app)
        if let cached = iconHistoryCache[key] {
            return cached
        }

        var entries: [AppIconHistoryEntry] = []
        var lastIcon: Data?

        for snapshot in snapshots.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let item = snapshot.apps.first(where: { comparisonKey(for: $0) == key }),
                  let iconData = item.iconData,
                  !iconData.isEmpty else {
                continue
            }
            if lastIcon == iconData { continue }

            entries.append(
                AppIconHistoryEntry(
                    snapshotID: snapshot.id,
                    snapshotName: snapshot.name,
                    capturedAt: snapshot.createdAt,
                    version: item.version,
                    build: item.build,
                    iconData: iconData
                )
            )
            lastIcon = iconData
        }

        iconHistoryCache[key] = entries
        return entries
    }

    /// 快照里是否出现过不止一个图标版本。
    func hasIconHistory(for app: AppRecord) -> Bool {
        iconHistory(for: app).count > 1
    }

    /// 汇总一个应用在全部历史快照中的档案。
    func appStory(for app: AppRecord) -> AppStory {
        let key = comparisonKey(for: app)
        let ordered = snapshots.sorted { $0.createdAt < $1.createdAt }

        var firstSeen: AppSnapshot?
        var lastSeen: AppSnapshot?
        var appearances = 0
        var versions: [AppStory.VersionEntry] = []
        var sourceChanges: [AppStory.SourceEntry] = []
        var lastVersion: String?
        var lastBuild: String?
        var lastSource: AppSource?

        for snapshot in ordered {
            guard let item = snapshot.apps.first(where: { comparisonKey(for: $0) == key }) else {
                continue
            }

            appearances += 1
            if firstSeen == nil { firstSeen = snapshot }
            lastSeen = snapshot

            let version = normalized(item.version)
            let build = normalized(item.build)
            if versions.isEmpty || version != lastVersion || build != lastBuild {
                versions.append(
                    AppStory.VersionEntry(
                        snapshotID: snapshot.id,
                        snapshotName: snapshot.name,
                        capturedAt: snapshot.createdAt,
                        version: item.version,
                        build: item.build,
                        source: item.source,
                        sizeInBytes: item.sizeInBytes
                    )
                )
                lastVersion = version
                lastBuild = build
            }

            if sourceChanges.isEmpty || item.source != lastSource {
                sourceChanges.append(
                    AppStory.SourceEntry(
                        snapshotID: snapshot.id,
                        snapshotName: snapshot.name,
                        capturedAt: snapshot.createdAt,
                        source: item.source
                    )
                )
                lastSource = item.source
            }
        }

        let liveKeys = Set(apps.map { comparisonKey(for: $0) })

        return AppStory(
            app: app,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            appearances: appearances,
            totalSnapshots: snapshots.count,
            versions: versions,
            sourceChanges: sourceChanges,
            iconHistory: iconHistory(for: app),
            isCurrentlyInstalled: liveKeys.contains(key)
        )
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// 最近快照里记录过、但当前已经没有安装的应用。
    var uninstalledSinceLastSnapshot: [AppRecord] {
        guard hasScanned, let snapshot = latestSnapshot else { return [] }
        let liveKeys = Set(apps.map { comparisonKey(for: $0) })
        return snapshot.apps.filter { !liveKeys.contains(comparisonKey(for: $0)) }
    }

    var newlyInstalledCount: Int { newlyInstalledApps.count }
    var updatedCount: Int { updatedApps.count }
    var uninstalledSinceLastSnapshotCount: Int { uninstalledSinceLastSnapshot.count }

    private static func iconSignature(for app: AppRecord) -> String {
        let updated = app.updatedAt?.timeIntervalSince1970 ?? 0
        return "\(app.version ?? "")|\(app.build ?? "")|\(updated)"
    }

    private static func versionChanged(from old: AppRecord, to new: AppRecord) -> Bool {
        let oldVersion = old.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newVersion = new.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !oldVersion.isEmpty || !newVersion.isEmpty {
            return oldVersion != newVersion
        }
        let oldBuild = old.build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newBuild = new.build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return oldBuild != newBuild
    }

    // MARK: - Filtering

    func filteredApps(_ input: [AppRecord], sortOrder: [KeyPathComparator<AppRecord>]) -> [AppRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.filter { app in
            let matchesSource = sourceFilter == nil
                || (app.source == sourceFilter && !(sourceFilter == .manual && app.isOwn))
                || (sourceFilter == app.managerSource && app.source != sourceFilter)
            let matchesPlatform = platformFilter == nil || app.platform == platformFilter
            let matchesType = typeFilter.matches(app)
            let matchesOwn = activeSelection != .own || app.isOwn
            let matchesSearch = query.isEmpty
                || app.name.localizedCaseInsensitiveContains(query)
                || app.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
                || app.path.localizedCaseInsensitiveContains(query)
                || app.source.title.localizedCaseInsensitiveContains(query)
            return matchesSource && matchesPlatform && matchesType && matchesOwn && matchesSearch
        }
        .sorted(using: sortOrder)
    }

    func filteredGalleryItems(_ input: [GalleryItem]) -> [GalleryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.filter { item in
            let matchesStatus = galleryStatusFilters.isEmpty
                || galleryStatusFilters.contains(item.status)
            let matchesSource = gallerySourceFilters.isEmpty
                || gallerySourceFilters.contains { source in
                    (item.app.source == source && !(source == .manual && item.app.isOwn))
                        || (source == item.app.managerSource && item.app.source != source)
                }
            let matchesPlatform = galleryPlatformFilters.isEmpty
                || galleryPlatformFilters.contains(item.app.platform)
            let matchesType = galleryTypeFilters.isEmpty
                || galleryTypeFilters.contains { $0.matches(item.app) }
            let matchesSearch = query.isEmpty
                || item.app.name.localizedCaseInsensitiveContains(query)
                || item.app.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
                || item.app.path.localizedCaseInsensitiveContains(query)
                || (item.snapshotName?.localizedCaseInsensitiveContains(query) == true)
            return matchesStatus && matchesSource && matchesPlatform && matchesType && matchesSearch
        }
    }

    func resetFilters() {
        searchText = ""
        sourceFilter = nil
        platformFilter = nil
        typeFilter = .all
        gallerySourceFilters = []
        galleryPlatformFilters = []
        galleryTypeFilters = []
        galleryStatusFilters = []
    }

    func syncSourceFilterForSelection() {
        switch activeSelection {
        case .source(let source):
            sourceFilter = source
        case .installed, .newlyInstalled, .updated, .uninstalled:
            sourceFilter = nil
        default:
            break
        }
    }

    var isSourceSelection: Bool {
        if case .source = activeSelection { return true }
        return false
    }

    // MARK: - Sidebar cache

    private func loadSidebarCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.sidebarCacheKey),
              let cache = try? JSONDecoder().decode(SidebarCache.self, from: data) else {
            return
        }
        cachedSidebar = cache
        if lastScanAt == nil {
            lastScanAt = cache.lastScanAt
        }
    }

    private func saveSidebarCache() {
        guard let lastScanAt else { return }

        let gallery = galleryItems
        let cache = SidebarCache(
            installedCount: apps.count,
            ownAppCount: apps.count { $0.isOwn },
            ownManualCount: apps.count { $0.isOwn && $0.source == .manual },
            galleryCount: gallery.count,
            uninstalledCount: gallery.count { $0.status == .uninstalled },
            sourceCounts: Dictionary(uniqueKeysWithValues: sourceCounts
                .map { ($0.key.rawValue, $0.value) }),
            lastScanAt: lastScanAt
        )

        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: Self.sidebarCacheKey)
        }
    }

    // MARK: - Scanning

    /// 扫描应用。
    ///
    /// - Parameter fullRefresh: 按住 ⌥ 点击刷新时使用。会丢掉体积缓存，
    ///   并让内存图标缓存失效、重写所有已安装应用的磁盘图标，
    ///   让所有图标和体积重新生成，而不是沿用旧数据。
    func refresh(ignoreRecentScan: Bool = false, fullRefresh: Bool = false) async {
        guard !isScanning, !isSavingSnapshot else { return }

        if !ignoreRecentScan,
           let lastScanAt,
           Date().timeIntervalSince(lastScanAt) < 20 {
            return
        }

        isScanning = true
        errorMessage = nil
        statusMessage = fullRefresh ? L.t("正在全量刷新应用…") : L.t("正在扫描应用…")

        enrichmentTask?.cancel()
        enrichmentToken = UUID()
        isEnriching = false
        iconPrefetchTask?.cancel()

        if fullRefresh {
            sizeCache.removeFile()
            sizeCache = SizeCache(fileURL: SizeCache.defaultFileURL)
            IconProvider.shared.clearMemoryCache()
        }

        var scannedApps = await scanner.scan()
        var cacheHits = 0

        if !fullRefresh {
            for index in scannedApps.indices {
                if let cachedSize = sizeCache.size(for: scannedApps[index]) {
                    scannedApps[index].sizeInBytes = cachedSize
                    cacheHits += 1
                }
            }
        }

        // 应用更新后路径不变，但版本 / 构建号 / 修改时间会变化。
        // 在把新列表交给界面之前先清掉这些应用的图标缓存，
        // 否则复用的表格行和内存缓存会继续显示旧图标。
        let previousByPath = Dictionary(
            apps.map { ($0.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hadScanned = hasScanned
        var iconChanges: [AppRecord] = []
        for app in scannedApps {
            guard let previous = previousByPath[app.path] else {
                // 首次扫描时相信磁盘缓存；之后扫描中新出现或重装的应用
                // 强制重写图标，避免沿用同 Bundle ID 的旧缓存。
                if hadScanned { iconChanges.append(app) }
                continue
            }
            if Self.iconSignature(for: previous) != Self.iconSignature(for: app) {
                iconChanges.append(app)
            }
        }
        if !iconChanges.isEmpty {
            IconProvider.shared.invalidate(apps: iconChanges)
            for app in iconChanges {
                if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                    IconDiskCache.remove(bundleID: bundleID)
                }
            }
        }
        let iconChangePaths = Set(iconChanges.map(\.path))

        apps = scannedApps
        hasScanned = true
        lastScanAt = Date()
        isScanning = false
        statusMessage = cacheHits > 0
            ? L.t("已找到 %d 个应用（缓存 %d）", scannedApps.count, cacheHits)
            : L.t("已找到 %d 个应用", scannedApps.count)
        saveSidebarCache()

        let iconApps = scannedApps
        iconPrefetchTask = Task {
            await IconProvider.shared.prefetch(
                apps: iconApps,
                forceDiskRewrite: fullRefresh,
                forcePaths: iconChangePaths
            )
        }

        // 当前筛选的来源如果已经不存在，自动回到全部来源。
        if let sourceFilter, (sourceCounts[sourceFilter] ?? 0) == 0 {
            self.sourceFilter = nil
        }

        // 「开发者的应用」分类只在 3 个及以上匹配应用时显示。
        if activeSelection == .own && ownAppCount <= 2 {
            sidebarSelection = .installed
            selectedAppID = nil
        }

        if let selectedAppID, !scannedApps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }

        beginSizeEnrichment()
    }

    func refreshIfStale() async {
        guard !isScanning else { return }
        if let lastScanAt, Date().timeIntervalSince(lastScanAt) < 30 { return }
        await refresh(ignoreRecentScan: true)
    }

    func clearSizeCacheAndRefresh() async {
        sizeCache.removeFile()
        sizeCache = SizeCache(fileURL: SizeCache.defaultFileURL)
        await refresh(ignoreRecentScan: true)
    }

    private func beginSizeEnrichment() {
        enrichmentTask?.cancel()
        let token = UUID()
        enrichmentToken = token

        let computeSizes = UserDefaults.standard.object(forKey: "computeSizes") as? Bool ?? true
        guard computeSizes else {
            isEnriching = false
            persistSizeCache()
            return
        }

        let pending = apps.filter { $0.sizeInBytes == nil }
        guard !pending.isEmpty else {
            isEnriching = false
            persistSizeCache()
            return
        }

        enrichmentDone = 0
        enrichmentTotal = pending.count
        isEnriching = true

        enrichmentTask = Task { [weak self] in
            await self?.computeSizes(records: pending, token: token)
        }
    }

    private func computeSizes(records: [AppRecord], token: UUID) async {
        let chunkSize = 12
        var start = 0

        while start < records.count {
            if Task.isCancelled || token != enrichmentToken { break }
            let end = min(start + chunkSize, records.count)
            let chunk = Array(records[start..<end])

            let updates = await withTaskGroup(of: (String, Int64).self) { group -> [(String, Int64)] in
                for record in chunk {
                    group.addTask {
                        let size = DirectorySize.bytes(at: URL(fileURLWithPath: record.resolvedPath))
                        return (record.path, size)
                    }
                }

                var results: [(String, Int64)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            guard token == enrichmentToken, !Task.isCancelled else { break }

            // 每 8 个应用批量写回一次，避免逐个应用刷新整张表。
            var updatedApps = apps
            var changed = false
            for (path, size) in updates {
                guard let index = updatedApps.firstIndex(where: { $0.path == path }) else { continue }
                updatedApps[index].sizeInBytes = size
                if size > 0 {
                    sizeCache.update(app: updatedApps[index], size: size)
                }
                changed = true
            }
            if changed {
                apps = updatedApps
            }
            enrichmentDone += updates.count
            start = end
        }

        if token == enrichmentToken {
            isEnriching = false
            enrichmentTask = nil
            persistSizeCache()
        }
    }

    private func computeSizesMap(for records: [AppRecord]) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        let chunkSize = 12
        var start = 0

        while start < records.count {
            let end = min(start + chunkSize, records.count)
            let chunk = Array(records[start..<end])

            await withTaskGroup(of: (String, Int64).self) { group in
                for record in chunk {
                    group.addTask {
                        let size = DirectorySize.bytes(at: URL(fileURLWithPath: record.resolvedPath))
                        return (record.path, size)
                    }
                }
                for await (path, size) in group {
                    result[path] = size
                }
            }

            start = end
        }

        return result
    }

    private func persistSizeCache() {
        sizeCache.prune(validPaths: Set(apps.map(\.resolvedPath)))
        sizeCache.save()
    }

    // MARK: - Snapshots

    func saveSnapshot() async {
        guard hasScanned, !isScanning, !isSavingSnapshot else { return }
        guard !apps.isEmpty else {
            errorMessage = L.t("当前扫描结果为空，无法保存快照。")
            return
        }

        isSavingSnapshot = true
        statusMessage = L.t("正在准备快照…")
        defer {
            isSavingSnapshot = false
        }

        // Homebrew 功能关闭时不读取，避免执行 brew 命令。
        // 与体积计算并行执行，不增加保存快照的等待时间。
        let brewInventoryTask = Task { () -> BrewInventory? in
            guard BrewStore.isEnabledPreference else { return nil }
            return await BrewService.loadInventory()
        }

        let preparedApps = await prepareSnapshotApps()
        let inventory = await brewInventoryTask.value
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let snapshot = AppSnapshot(
            name: formatter.string(from: now),
            createdAt: now,
            apps: preparedApps,
            casks: inventory?.casks.map(BrewCaskRecord.init(from:)) ?? [],
            brewVersion: inventory?.brewVersion
        )

        snapshots.insert(snapshot, at: 0)
        sidebarSelection = .snapshot(snapshot.id)
        selectedAppID = nil
        persist(snapshot)
        statusMessage = L.t("已保存快照 · %@ · %d 个应用", snapshot.name, snapshot.appCount)
    }

    /// 等待后台体积计算完成，补齐所有体积与图标后再写入快照。
    private func prepareSnapshotApps() async -> [AppRecord] {
        if let enrichmentTask {
            await enrichmentTask.value
        }

        var result = apps
        let missingSizes = result.filter { $0.sizeInBytes == nil }

        if !missingSizes.isEmpty {
            let sizes = await computeSizesMap(for: missingSizes)
            var updatedLiveApps = apps
            for index in result.indices where result[index].sizeInBytes == nil {
                guard let size = sizes[result[index].path] else { continue }
                result[index].sizeInBytes = size
                if size > 0 {
                    sizeCache.update(app: result[index], size: size)
                }
                if let liveIndex = updatedLiveApps.firstIndex(where: { $0.path == result[index].path }) {
                    updatedLiveApps[liveIndex].sizeInBytes = size
                }
            }
            apps = updatedLiveApps
            persistSizeCache()
        }

        let missingIconPaths = result.filter { $0.iconData == nil }.map(\.path)
        if !missingIconPaths.isEmpty {
            // 快照图标会长期使用（应用卸载后只剩这份数据），
            // 按 192px 保存，足够在 Retina 列表和详情里清晰显示。
            let icons = await IconProvider.renderPNGs(for: missingIconPaths, pixelSize: 192)
            for index in result.indices where result[index].iconData == nil {
                result[index].iconData = icons[result[index].path]
            }
        }

        return result
    }

    func deleteSnapshot(id: UUID) {
        snapshots.removeAll { $0.id == id }
        if case .snapshot(let selectedID) = activeSelection, selectedID == id {
            sidebarSelection = .installed
            selectedAppID = nil
        }
        do {
            try repository.delete(id: id)
        } catch {
            errorMessage = L.t("无法删除快照文件：%@", error.localizedDescription)
        }
        statusMessage = L.t("已删除快照")
    }

    func renameSnapshot(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[index].name = trimmed
        persist(snapshots[index])
    }

    func updateSnapshotNote(id: UUID, note: String) {
        guard let index = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[index].note = note
        persist(snapshots[index])
    }

    func importSnapshots(from url: URL) {
        do {
            let imported = try repository.decodeImport(from: url)
            guard !imported.isEmpty else {
                errorMessage = L.t("所选文件中没有可导入的快照。")
                return
            }

            let incomingIDs = Set(imported.map(\.id))
            snapshots.removeAll { incomingIDs.contains($0.id) }
            snapshots.append(contentsOf: imported)
            snapshots.sort { $0.createdAt > $1.createdAt }
            try repository.save(imported)

            if let first = imported.sorted(by: { $0.createdAt > $1.createdAt }).first {
                sidebarSelection = .snapshot(first.id)
                selectedAppID = nil
            }
            statusMessage = L.t("已导入 %d 个快照", imported.count)
        } catch {
            errorMessage = L.t("无法导入快照：%@", error.localizedDescription)
        }
    }

    func exportSnapshot(_ snapshot: AppSnapshot, to url: URL) {
        do {
            try repository.export(snapshot, to: url)
            statusMessage = L.t("已导出快照 · %@", snapshot.name)
        } catch {
            errorMessage = L.t("无法导出快照：%@", error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        do {
            snapshots = try repository.load().sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = L.t("无法读取快照：%@", error.localizedDescription)
        }
    }

    private func persist(_ snapshot: AppSnapshot) {
        do {
            try repository.save(snapshot)
        } catch {
            errorMessage = L.t("无法保存快照：%@", error.localizedDescription)
        }
    }
}
