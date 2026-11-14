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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packages: L.t("包")
        case .snapshots: L.t("快照")
        }
    }

    var symbol: String {
        switch self {
        case .packages: "shippingbox"
        case .snapshots: "camera"
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

    /// 启动时解析一次 brew 路径，避免在视图 body 中反复访问文件系统。
    let executableURL = BrewService.locateExecutable()

    private var runningProcess: BrewProcess?
    private let snapshotRepository = BrewSnapshotRepository()

    init() {
        loadSnapshots()
    }

    // MARK: - 状态

    var isAvailable: Bool { executableURL != nil }

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
        // 没有安装 Homebrew 时界面会显示引导状态，无需弹出错误。
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

    func cleanup() async {
        _ = await runCommand(["cleanup"], title: L.t("清理缓存与旧版本"))
    }

    func autoremove() async {
        _ = await runCommand(["autoremove"], title: L.t("移除不再需要的依赖"))
    }

    func doctor() async {
        _ = await runCommand(["doctor"], title: L.t("检查 Homebrew 环境"), refreshAfter: false)
    }

    func showConfig() async {
        _ = await runCommand(["config"], title: L.t("查看 Homebrew 配置"), refreshAfter: false)
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
