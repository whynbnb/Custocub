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
    case snapshots
    case cleanup
    case health

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packages: L.t("包")
        case .snapshots: L.t("快照")
        case .cleanup: L.t("清理")
        case .health: L.t("配置与诊断")
        }
    }

    var symbol: String {
        switch self {
        case .packages: "shippingbox"
        case .snapshots: "camera"
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

    @Published var searchText = ""
    @Published var kindFilter: BrewPackageKind?
    @Published var showsOutdatedOnly = false
    @Published var showsPinnedOnly = false

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
        loadSnapshots()
    }

    // MARK: - 状态

    /// 是否检测到 Homebrew 可执行文件。
    var isInstalled: Bool { executableURL != nil }

    /// 功能是否可用：用户开启且本机确实安装了 Homebrew。
    var isAvailable: Bool { isEnabled && isInstalled }

    /// 用户主动关闭时为 true。
    var isDisabledByUser: Bool { !isEnabled }

    /// 开启开关但本机未安装 Homebrew。
    var isMissingInstallation: Bool { isEnabled && !isInstalled }

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
        inventory?.brewVersion ?? L.t("未知")
    }

    var prefix: String {
        inventory?.prefix ?? L.t("未知")
    }

    var dependencyCount: Int {
        formulae.count(where: \.isDependency)
    }

    var filteredPackages: [BrewPackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return packages.filter { package in
            let matchesKind = kindFilter == nil || package.kind == kindFilter
            let matchesOutdated = !showsOutdatedOnly || package.isOutdated
            let matchesPinned = !showsPinnedOnly || package.isPinned
            let matchesSearch = query.isEmpty
                || package.name.localizedCaseInsensitiveContains(query)
                || package.title.localizedCaseInsensitiveContains(query)
                || (package.summary?.localizedCaseInsensitiveContains(query) == true)
                || (package.tap?.localizedCaseInsensitiveContains(query) == true)
                || (package.installedVersion?.localizedCaseInsensitiveContains(query) == true)
            return matchesKind && matchesOutdated && matchesPinned && matchesSearch
        }
    }

    func package(id: String?) -> BrewPackage? {
        guard let id else { return nil }
        return inventory?.package(id: id)
    }

    var selectedPackage: BrewPackage? {
        package(id: selectedPackageID)
    }

    func resetFilters() {
        searchText = ""
        kindFilter = nil
        showsOutdatedOnly = false
        showsPinnedOnly = false
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
        defer { isLoading = false }

        if let loaded = await BrewService.loadInventory() {
            inventory = loaded
            lastLoadedAt = Date()
            hasLoaded = true
            if let selectedPackageID, loaded.package(id: selectedPackageID) == nil {
                self.selectedPackageID = nil
            }
        } else {
            errorMessage = L.t("无法读取 Homebrew 包列表。")
        }
    }

    // MARK: - 命令执行

    /// 执行一条 brew 命令，并把输出实时写入日志。
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
        lastLoadedAt = nil
        selection.removeAll()
        selectedPackageID = nil
        appendLog(.info, L.t("Homebrew 功能已关闭，不再执行任何 brew 命令。"))
    }

    /// 重新检测本机是否安装了 Homebrew。
    func rediscover() {
        executableURL = BrewService.locateExecutable()
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
        let formulae = packages.filter { $0.kind == .formula }.map(\.name)
        let casks = packages.filter { $0.kind == .cask }.map(\.name)

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
        let names = packages.map(\.name)
        _ = await runCommand(
            ["upgrade"] + names,
            title: L.t("升级 %@", names.joined(separator: ", "))
        )
    }

    func upgradeAll() async {
        _ = await runCommand(["upgrade"], title: L.t("升级全部可更新包"))
    }

    func reinstall(_ package: BrewPackage) async {
        _ = await runCommand(
            ["reinstall"] + (package.kind == .cask ? ["--cask"] : []) + [package.name],
            title: L.t("重新安装 %@", package.name)
        )
    }

    func pin(_ package: BrewPackage) async {
        _ = await runCommand(
            ["pin"] + (package.kind == .cask ? ["--cask"] : []) + [package.name],
            title: L.t("固定 %@", package.name)
        )
    }

    func unpin(_ package: BrewPackage) async {
        _ = await runCommand(
            ["unpin"] + (package.kind == .cask ? ["--cask"] : []) + [package.name],
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

        snapshots.insert(snapshot, at: 0)
        persist(snapshot)
    }

    func deleteSnapshot(id: UUID) {
        snapshots.removeAll { $0.id == id }
        do {
            try snapshotRepository.delete(id: id)
        } catch {
            errorMessage = L.t("无法删除 Homebrew 快照：%@", error.localizedDescription)
        }
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

    private func persist(_ snapshot: BrewSnapshot) {
        do {
            try snapshotRepository.save(snapshot)
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
            formulae: inventory.formulae.map(\.name),
            casks: inventory.casks.map(\.name),
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
            formulae: inventory.formulae.map(\.name),
            casks: [],
            header: L.t("由 Custocub 生成 · %@ · Formula", Date().formatted(date: .abbreviated, time: .shortened))
        )
        BrewExport.save(text: text, suggestedName: "Brewfile-Formula", contentType: .brewfile)
    }

    func exportCurrentCasks() {
        guard let inventory else { return }
        let text = BrewfileBuilder.text(
            formulae: [],
            casks: inventory.casks.map(\.name),
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

    /// 常用维护命令：更新索引、清理、检查、自动移除无用依赖。
    func updateIndex() async {
        _ = await runCommand(["update"], title: L.t("更新 Homebrew 索引"))
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
    /// 移除过期下载、旧版本 keg、残留锁文件和日志，并自动移除无用依赖。
    func cleanupStandard() async {
        lastCleanupFreedBytes = cleanupReport?.estimatedFreeBytes
        await runCommand(["cleanup"], title: L.t("清理缓存与旧版本"))
        await analyzeCleanup(force: true)
    }

    /// 深度清理：等价于 `brew cleanup --prune=all`。
    /// 删除所有缓存下载（包括最新版本），能释放最多空间。
    func cleanupAll() async {
        lastCleanupFreedBytes = cleanupReport?.estimatedFreeBytes
        await runCommand(["cleanup", "--prune=all"], title: L.t("清理全部缓存"))
        await analyzeCleanup(force: true)
    }

    /// 彻底清空下载缓存目录，等价于删除 `$(brew --cache)`。
    /// 下次安装或升级时会重新下载。
    func cleanupEverything() async {
        lastCleanupFreedBytes = cleanupReport?.estimatedFreeBytes
        await runCommand(
            ["cleanup", "--prune=all", "--scrub"],
            title: L.t("清空下载缓存")
        )
        await analyzeCleanup(force: true)
    }

    /// 试运行清理，只显示会删除什么。
    func cleanupDryRun() async {
        await runCommand(["cleanup", "-n"], title: L.t("预览清理内容"), refreshAfter: false)
    }

    /// 只清理某个包的旧版本。
    func cleanupPackage(_ package: BrewPackage) async {
        await runCommand(
            ["cleanup"] + (package.kind == .cask ? ["--cask"] : []) + [package.name],
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
        _ = await runCommand(["outdated", "--verbose"], title: L.t("查看可更新的包"), refreshAfter: false)
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
