import AppKit
import Foundation

enum SidebarSelection: Hashable {
    case installed
    case gallery
    case snapshot(UUID)
}

enum AppTypeFilter: String, CaseIterable, Identifiable {
    case all
    case system
    case thirdParty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部类型"
        case .system: "系统应用"
        case .thirdParty: "第三方应用"
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
}

@MainActor
final class CustocubStore: ObservableObject {
    @Published private(set) var apps: [AppRecord] = []
    @Published private(set) var snapshots: [AppSnapshot] = []
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
    @Published var galleryStatusFilter: GalleryItem.Status?
    @Published var sortOrder: [KeyPathComparator<AppRecord>] = [
        KeyPathComparator(\AppRecord.name, order: .forward)
    ]

    private let repository: SnapshotRepository
    private let scanner: AppScanner
    private var enrichmentTask: Task<Void, Never>?
    private var enrichmentToken = UUID()
    private let liveSnapshotID = UUID()

    init(
        repository: SnapshotRepository = SnapshotRepository(),
        scanner: AppScanner = AppScanner()
    ) {
        self.repository = repository
        self.scanner = scanner
        loadSnapshots()
    }

    // MARK: - Derived data

    var activeSelection: SidebarSelection {
        sidebarSelection ?? .installed
    }

    var installedCount: Int { apps.count }
    var systemCount: Int { apps.count { $0.isSystemApp } }
    var thirdPartyCount: Int { apps.count { !$0.isSystemApp } }

    var sourceCounts: [AppSource: Int] {
        Dictionary(grouping: apps, by: \.source).mapValues(\.count)
    }

    var totalSize: Int64 {
        apps.compactMap(\.sizeInBytes).reduce(0, +)
    }

    var totalSizeText: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var liveSnapshot: AppSnapshot? {
        guard hasScanned else { return nil }
        return AppSnapshot(
            id: liveSnapshotID,
            name: "当前状态",
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
        case .installed:
            guard let app = apps.first(where: { $0.id == selectedAppID }) else { return nil }
            return SelectedAppContext(app: app, galleryItem: nil, snapshot: nil)

        case .gallery:
            if let item = galleryItems.first(where: { $0.app.id == selectedAppID }) {
                return SelectedAppContext(app: item.app, galleryItem: item, snapshot: nil)
            }
            guard let app = apps.first(where: { $0.id == selectedAppID }) else { return nil }
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

    var uninstalledCount: Int {
        guard hasScanned else { return 0 }
        return galleryItems.count { $0.status == .uninstalled }
    }

    // MARK: - Filtering

    func filteredApps(_ input: [AppRecord]) -> [AppRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.filter { app in
            let matchesSource = sourceFilter == nil || app.source == sourceFilter
            let matchesPlatform = platformFilter == nil || app.platform == platformFilter
            let matchesType = typeFilter.matches(app)
            let matchesSearch = query.isEmpty
                || app.name.localizedCaseInsensitiveContains(query)
                || app.bundleIdentifier?.localizedCaseInsensitiveContains(query) == true
                || app.path.localizedCaseInsensitiveContains(query)
                || app.source.title.localizedCaseInsensitiveContains(query)
            return matchesSource && matchesPlatform && matchesType && matchesSearch
        }
        .sorted(using: sortOrder)
    }

    func filteredGalleryItems(_ input: [GalleryItem]) -> [GalleryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return input.filter { item in
            let matchesStatus = galleryStatusFilter == nil || item.status == galleryStatusFilter
            let matchesSource = sourceFilter == nil || item.app.source == sourceFilter
            let matchesPlatform = platformFilter == nil || item.app.platform == platformFilter
            let matchesType = typeFilter.matches(item.app)
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
        galleryStatusFilter = nil
    }

    /// 侧边栏的来源快捷筛选：切回已安装列表并应用来源过滤。
    func applySourceFilter(_ source: AppSource?) {
        sourceFilter = source
        sidebarSelection = .installed
        selectedAppID = nil
    }

    // MARK: - Scanning

    func refresh(ignoreRecentScan: Bool = false) async {
        guard !isScanning, !isSavingSnapshot else { return }

        if !ignoreRecentScan,
           let lastScanAt,
           Date().timeIntervalSince(lastScanAt) < 20 {
            return
        }

        isScanning = true
        errorMessage = nil
        statusMessage = "正在扫描应用…"

        enrichmentTask?.cancel()
        enrichmentToken = UUID()
        isEnriching = false

        let scannedApps = await scanner.scan()
        apps = scannedApps
        hasScanned = true
        lastScanAt = Date()
        isScanning = false
        statusMessage = "已找到 \(scannedApps.count) 个应用"
        IconProvider.shared.clear()

        // 当前筛选的来源如果已经不存在，自动回到全部来源。
        if let sourceFilter, (sourceCounts[sourceFilter] ?? 0) == 0 {
            self.sourceFilter = nil
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

    private func beginSizeEnrichment() {
        enrichmentTask?.cancel()
        let token = UUID()
        enrichmentToken = token

        let computeSizes = UserDefaults.standard.object(forKey: "computeSizes") as? Bool ?? true
        guard computeSizes else {
            isEnriching = false
            return
        }

        let pending = apps.filter { $0.sizeInBytes == nil }
        guard !pending.isEmpty else {
            isEnriching = false
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
        let chunkSize = 8
        var start = 0

        while start < records.count {
            if Task.isCancelled || token != enrichmentToken { break }
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
                    guard token == self.enrichmentToken, !Task.isCancelled else { continue }
                    if let index = self.apps.firstIndex(where: { $0.path == path }) {
                        self.apps[index].sizeInBytes = size
                    }
                    self.enrichmentDone += 1
                }
            }

            start = end
        }

        if token == enrichmentToken {
            isEnriching = false
            enrichmentTask = nil
        }
    }

    private func computeSizesMap(for records: [AppRecord]) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        let chunkSize = 8
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

    // MARK: - Snapshots

    func saveSnapshot() async {
        guard hasScanned, !isScanning, !isSavingSnapshot else { return }
        guard !apps.isEmpty else {
            errorMessage = "当前扫描结果为空，无法保存快照。"
            return
        }

        isSavingSnapshot = true
        statusMessage = "正在准备快照…"
        defer {
            isSavingSnapshot = false
        }

        let preparedApps = await prepareSnapshotApps()
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let snapshot = AppSnapshot(
            name: formatter.string(from: now),
            createdAt: now,
            apps: preparedApps
        )

        snapshots.insert(snapshot, at: 0)
        sidebarSelection = .snapshot(snapshot.id)
        selectedAppID = nil
        persist(snapshot)
        statusMessage = "已保存快照 · \(snapshot.name) · \(snapshot.appCount) 个应用"
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
            for index in result.indices where result[index].sizeInBytes == nil {
                if let size = sizes[result[index].path] {
                    result[index].sizeInBytes = size
                    if let liveIndex = apps.firstIndex(where: { $0.path == result[index].path }) {
                        apps[liveIndex].sizeInBytes = size
                    }
                }
            }
        }

        let missingIconPaths = result.filter { $0.iconData == nil }.map(\.path)
        if !missingIconPaths.isEmpty {
            let icons = await IconProvider.renderPNGs(for: missingIconPaths, pixelSize: 128)
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
            errorMessage = "无法删除快照文件：\(error.localizedDescription)"
        }
        statusMessage = "已删除快照"
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
                errorMessage = "所选文件中没有可导入的快照。"
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
            statusMessage = "已导入 \(imported.count) 个快照"
        } catch {
            errorMessage = "无法导入快照：\(error.localizedDescription)"
        }
    }

    func exportSnapshot(_ snapshot: AppSnapshot, to url: URL) {
        do {
            try repository.export(snapshot, to: url)
            statusMessage = "已导出快照 · \(snapshot.name)"
        } catch {
            errorMessage = "无法导出快照：\(error.localizedDescription)"
        }
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        do {
            snapshots = try repository.load().sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = "无法读取快照：\(error.localizedDescription)"
        }
    }

    private func persist(_ snapshot: AppSnapshot) {
        do {
            try repository.save(snapshot)
        } catch {
            errorMessage = "无法保存快照：\(error.localizedDescription)"
        }
    }
}
