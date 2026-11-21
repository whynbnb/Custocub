import AppKit
import SwiftUI

struct InstalledAppsView: View {
    @EnvironmentObject private var store: CustocubStore

    private var isOwnMode: Bool { store.activeSelection == .own }

    var body: some View {
        VStack(spacing: 0) {
            if isOwnMode {
                OwnAppsHeader()
            } else {
                InstalledHeader()
            }
            Divider()
            FilterBar()
            Divider()
            AppTable(
                apps: store.apps,
                emptyMessage: isOwnMode
                    ? L.t("没有匹配个人应用前缀的应用")
                    : (store.hasScanned ? L.t("没有发现应用") : L.t("尚未扫描。点击工具栏的「扫描应用」开始。"))
            )
        }
        .navigationTitle(isOwnMode ? L.t("开发者的应用") : L.t("已安装应用"))
    }
}

/// 「新安装」：最近一次快照之后新装的应用。
struct NewlyInstalledAppsView: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = store.latestSnapshot {
                ComparisonHeaderView(
                    title: "新安装",
                    symbol: "plus.app.fill",
                    tint: .teal,
                    count: store.newlyInstalledCount,
                    summary: "最近快照之后新安装的应用",
                    snapshot: snapshot
                )
                Divider()
                FilterBar()
                Divider()
                AppTable(apps: store.newlyInstalledApps, emptyMessage: "没有新安装的应用")
            } else {
                NoSnapshotPrompt()
            }
        }
        .navigationTitle("新安装")
    }
}

/// 「已更新」：与最近一次快照相比，版本发生变化的应用。
struct UpdatedAppsView: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = store.latestSnapshot {
                ComparisonHeaderView(
                    title: "已更新",
                    symbol: "arrow.up.circle.fill",
                    tint: .blue,
                    count: store.updatedCount,
                    summary: "版本与最近快照不同的应用",
                    snapshot: snapshot
                )
                Divider()
                FilterBar()
                Divider()
                AppTable(apps: store.updatedApps, emptyMessage: "没有版本变化的应用")
            } else {
                NoSnapshotPrompt()
            }
        }
        .navigationTitle("已更新")
    }
}

/// 「已卸载」：最近一次快照里记录过、但当前没有安装的应用。
struct UninstalledAppsView: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(spacing: 0) {
            if let snapshot = store.latestSnapshot {
                ComparisonHeaderView(
                    title: "已卸载",
                    symbol: "archivebox.fill",
                    tint: .red,
                    count: store.uninstalledSinceLastSnapshotCount,
                    summary: "最近快照里有、但当前没有安装的应用",
                    snapshot: snapshot
                )
                Divider()
                FilterBar()
                Divider()
                AppTable(apps: store.uninstalledSinceLastSnapshot, emptyMessage: "最近快照里的应用都还装着")
            } else {
                NoSnapshotPrompt()
            }
        }
        .navigationTitle("已卸载")
    }
}

/// 「已更新」「已卸载」共用的头部：说明对比基准，避免误解成实时状态。
private struct ComparisonHeaderView: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let summary: String
    let snapshot: AppSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(LocalizedStringKey(title))
                    .font(.title2.weight(.semibold))
                Spacer(minLength: 12)
                Text(L.t("%d 个应用", count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(LocalizedStringKey(summary))
                Text("·")
                Text(L.t("对比快照「%@」", snapshot.name))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(16)
        .background(.background)
    }
}

private struct NoSnapshotPrompt: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        ContentUnavailableView {
            Label("还没有快照", systemImage: "camera.badge.ellipsis")
        } description: {
            Text("保存一个快照后，才能对比出已更新和已卸载的应用。")
        } actions: {
            Button("保存快照") {
                Task { await store.saveSnapshot() }
            }
            .disabled(store.isScanning || store.isSavingSnapshot || !store.hasScanned || store.apps.isEmpty)
        }
    }
}

struct SnapshotAppsView: View {
    @EnvironmentObject private var store: CustocubStore
    let snapshot: AppSnapshot

    @State private var showsCasks = false

    var body: some View {
        VStack(spacing: 0) {
            SnapshotHeaderView(snapshot: snapshot, showsCasks: $showsCasks)
            Divider()

            if showsCasks {
                SnapshotCaskListView(snapshot: snapshot)
            } else {
                FilterBar()
                Divider()
                AppTable(apps: snapshot.apps, emptyMessage: L.t("这个快照中没有符合条件的应用"))
            }
        }
        .navigationTitle(snapshot.name)
    }
}

/// 应用快照中记录的 Homebrew Cask 列表，可直接导出安装命令。
struct SnapshotCaskListView: View {
    @EnvironmentObject private var brewStore: BrewStore
    let snapshot: AppSnapshot
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "mug.fill")
                    .foregroundStyle(AppSource.homebrew.color)
                Text(L.t("这个快照记录了 %d 个 Homebrew Cask", snapshot.caskCount))
                    .font(.callout)
                if brewStore.isRunningCommand {
                    ProgressView().controlSize(.small)
                    Text(L.t("正在执行…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(L.t("复制安装命令")) {
                    BrewExport.copy(snapshot.caskInstallCommand)
                }
                .controlSize(.small)

                Button(L.t("复制 Brewfile")) {
                    BrewExport.copy(snapshot.brewfileText)
                }
                .controlSize(.small)

                Menu {
                    Button(L.t("导出 Brewfile…")) {
                        BrewExport.save(
                            text: snapshot.brewfileText,
                            suggestedName: "Brewfile-Cask-\(snapshot.name)",
                            contentType: .brewfile
                        )
                    }
                    Divider()
                    Button(L.t("导出安装脚本…")) {
                        BrewExport.save(
                            text: "#!/bin/bash\n" + snapshot.caskInstallCommand + "\n",
                            suggestedName: "install-casks-\(snapshot.name).sh",
                            contentType: .shellScript
                        )
                    }
                } label: {
                    Label(L.t("导出"), systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.bar)

            Divider()

            Table(snapshot.casks, selection: $selection) {
                TableColumn("Cask") { cask in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cask.name ?? cask.token)
                            .lineLimit(1)
                        Text(cask.token)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
                .width(min: 220, ideal: 300, max: 400)

                TableColumn("版本") { cask in
                    Text(cask.version ?? L.t("未知"))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .width(min: 80, ideal: 110, max: 160)

                TableColumn("Tap") { cask in
                    Text(cask.tap ?? "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 120, max: 170)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let tokens = snapshot.casks.filter { ids.contains($0.id) }.map(\.token)
                let targets = tokens.isEmpty ? snapshot.caskTokens : tokens
                if !targets.isEmpty {
                    Button(L.t("复制安装命令")) {
                        BrewExport.copy(BrewPackage.command("install", kind: .cask, names: targets))
                    }
                    Button(L.t("复制包名")) {
                        BrewExport.copy(BrewfileBuilder.plainList(targets))
                    }
                    Divider()
                    Button(L.t("安装选中的 Cask")) {
                        Task { await brewStore.install(targets, kind: .cask) }
                    }
                }
            }
        }
    }
}

private struct InstalledHeader: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 总数、系统、第三方是整体统计，用无底色的数字组呈现；
            // 下面的指标行是分来源明细，继续用彩色胶囊。两种样式区分层级。
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 7) {
                    Text("已安装应用")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("扫描 /Applications、~/Applications 与系统应用目录，并识别每个应用的来源和架构。")
                        .accessibilityLabel("扫描说明")
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    HeaderStat(title: "应用", value: store.installedCount, symbol: "square.grid.2x2", color: .accentColor)
                    HeaderStatDivider()
                    HeaderStat(title: "系统", value: store.systemCount, symbol: "apple.logo", color: .secondary)
                    HeaderStatDivider()
                    HeaderStat(title: "第三方", value: store.thirdPartyCount, symbol: "shippingbox", color: .green)
                }
                .fixedSize()
            }

            MetricChipRow {
                MetricChip(title: "App Store", value: "\(store.sourceCounts[.appStore, default: 0] + store.sourceCounts[.appStoreIOS, default: 0])", symbol: "bag", color: .blue)
                MetricChip(title: "Homebrew", value: "\(store.sourceCounts[.homebrew, default: 0])", symbol: "mug", color: .orange)
                if store.sourceCounts[.steam, default: 0] > 0 {
                    MetricChip(title: "Steam", value: "\(store.sourceCounts[.steam, default: 0])", symbol: "gamecontroller", color: AppSource.steam.color)
                }
                if store.sourceCounts[.jetbrainsToolbox, default: 0] > 0 {
                    MetricChip(title: "Toolbox", value: "\(store.sourceCounts[.jetbrainsToolbox, default: 0])", symbol: "wrench.and.screwdriver", color: AppSource.jetbrainsToolbox.color)
                }
                MetricChip(title: "占用", value: store.totalSizeText, symbol: "internaldrive", color: .purple)
            }
        }
        .padding(16)
        .background(.background)
    }
}

private struct OwnAppsHeader: View {
    @EnvironmentObject private var store: CustocubStore

    private var prefix: String {
        AppConstants.developerBundlePrefix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text("开发者的应用")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(Text(L.t("Bundle ID 前缀：%@", prefix)))
                        .accessibilityLabel("开发者应用说明")
                }
                Spacer()
                Text(L.t("%d 个应用", store.ownAppCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            MetricChipRow {
                MetricChip(
                    title: "开发者的应用",
                    value: "\(store.ownAppCount)",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    color: .purple
                )
                MetricChip(
                    title: "占用",
                    value: store.ownTotalSizeText,
                    symbol: "internaldrive",
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(.background)
    }
}

private struct SnapshotHeaderView: View {
    @EnvironmentObject private var store: CustocubStore
    let snapshot: AppSnapshot
    @Binding var showsCasks: Bool

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var noteDraft = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.orange)

                if isEditingName {
                    TextField("快照名称", text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .focused($nameFocused)
                        .onSubmit(commitName)
                } else {
                    Text(snapshot.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            nameDraft = snapshot.name
                            isEditingName = true
                            nameFocused = true
                        }
                }

                Button {
                    if isEditingName {
                        commitName()
                    } else {
                        nameDraft = snapshot.name
                        isEditingName = true
                        nameFocused = true
                    }
                } label: {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text(L.t(isEditingName ? "完成重命名" : "重命名快照")))

                Spacer()

                HStack(spacing: 6) {
                    Label(snapshot.hostName, systemImage: "desktopcomputer")
                    Text("·")
                    Text(snapshot.osVersion)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)

                Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            MetricChipRow {
                MetricChip(title: "应用", value: "\(snapshot.appCount)", symbol: "square.grid.2x2", color: .accentColor)
                MetricChip(title: "系统", value: "\(snapshot.systemCount)", symbol: "apple.logo", color: .secondary)
                MetricChip(title: "第三方", value: "\(snapshot.thirdPartyCount)", symbol: "shippingbox", color: .green)
                MetricChip(title: "App Store", value: "\(snapshot.appStoreCount)", symbol: "bag", color: .blue)
                MetricChip(title: "Homebrew", value: "\(snapshot.homebrewCount)", symbol: "mug", color: .orange)
                if snapshot.caskCount > 0 {
                    MetricChip(title: "Cask", value: "\(snapshot.caskCount)", symbol: "shippingbox", color: .orange)
                }
                if snapshot.sourceCounts[.steam, default: 0] > 0 {
                    MetricChip(title: "Steam", value: "\(snapshot.sourceCounts[.steam, default: 0])", symbol: "gamecontroller", color: AppSource.steam.color)
                }
                if snapshot.sourceCounts[.jetbrainsToolbox, default: 0] > 0 {
                    MetricChip(title: "Toolbox", value: "\(snapshot.sourceCounts[.jetbrainsToolbox, default: 0])", symbol: "wrench.and.screwdriver", color: AppSource.jetbrainsToolbox.color)
                }
                MetricChip(title: "占用", value: snapshot.totalSizeText, symbol: "internaldrive", color: .purple)
            }

            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                TextField("为这个快照添加备注…", text: $noteDraft)
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
                    .onSubmit(commitNote)
                    .layoutPriority(0)

                if noteFocused {
                    Button("保存备注", action: commitNote)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer(minLength: 8)

                if !snapshot.casks.isEmpty {
                    Picker("内容", selection: $showsCasks) {
                        Text(L.t("应用")).tag(false)
                        Text(L.t("Cask (%d)", snapshot.caskCount)).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    .layoutPriority(1)
                }
            }
            .font(.callout)
        }
        .padding(16)
        .background(.background)
        .onAppear {
            nameDraft = snapshot.name
            noteDraft = snapshot.note
        }
        .onChange(of: snapshot.id) {
            nameDraft = snapshot.name
            noteDraft = snapshot.note
            isEditingName = false
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused && isEditingName { commitName() }
        }
        .onChange(of: noteFocused) { _, focused in
            if !focused { commitNote() }
        }
        .onDisappear {
            commitNote()
            if isEditingName { commitName() }
        }
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = snapshot.name
            isEditingName = false
            return
        }
        store.renameSnapshot(id: snapshot.id, name: trimmed)
        isEditingName = false
    }

    private func commitNote() {
        guard noteDraft != snapshot.note else { return }
        store.updateSnapshotNote(id: snapshot.id, note: noteDraft)
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    /// 空间不足时只显示图标与数值，标题放进悬停提示。
    var showsTitle = true
    /// 作为快捷筛选时，标记当前是否生效。
    var isActive = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
            if showsTitle {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(
            color.opacity(isActive ? 0.18 : 0.08),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(color.opacity(0.55), lineWidth: 1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .help(Text("\(L.t(title)): \(value)"))
    }
}

private struct MetricChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                content
            }
            .padding(.vertical, 1)
        }
    }
}

/// 标题行里的总体统计，不带底色，与下方的来源胶囊区分层级。
private struct HeaderStat: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .help(Text("\(L.t(title)): \(value)"))
        .accessibilityElement(children: .combine)
    }
}

private struct HeaderStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 16)
    }
}

private struct AppTable: View {
    @EnvironmentObject private var store: CustocubStore
    let apps: [AppRecord]
    let emptyMessage: String

    @State private var sortOrder: [KeyPathComparator<AppRecord>] = [
        KeyPathComparator(\AppRecord.name, order: .forward)
    ]
    @State private var selection: String?

    private var filtered: [AppRecord] {
        store.filteredApps(apps, sortOrder: sortOrder)
    }

    var body: some View {
        Table(filtered, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("应用", value: \.name) { app in
                HStack(spacing: 9) {
                    AppIconView(app: app, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(app.name)
                                .lineLimit(1)
                            if store.isManagerNode(app) {
                                ManagerBadge()
                            }
                        }
                        Text(app.listSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .width(min: 220, ideal: 300, max: 380)

            TableColumn("版本", value: \.versionSortValue) { app in
                Text(app.displayVersion)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 80, max: 110)

            TableColumn("来源") { app in
                SourceBadge(source: app.source, compact: true)
            }
            .width(min: 90, ideal: 112, max: 150)

            TableColumn("平台") { app in
                PlatformBadge(platform: app.platform)
            }
            .width(min: 80, ideal: 100, max: 140)

            TableColumn("类型") { app in
                TypeBadge(isSystem: app.isSystemApp)
            }
            .width(min: 80, ideal: 96, max: 130)

            TableColumn("大小", value: \.sizeSortValue) { app in
                Text(app.displaySize)
                    .monospacedDigit()
                    .foregroundStyle(app.sizeInBytes == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 90, max: 130)

            TableColumn("更新于", value: \.updatedSortValue) { app in
                Text(app.updatedAtListText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 112, max: 155)
        }
        .overlay {
            if filtered.isEmpty {
                if store.isScanning && apps.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在扫描应用…")
                            .foregroundStyle(.secondary)
                    }
                } else if store.searchText.isEmpty && !hasActiveFilter {
                    ContentUnavailableView(emptyMessage, systemImage: "app.dashed")
                } else {
                    ContentUnavailableView(
                        "没有符合条件的应用",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("请调整搜索内容或筛选条件。")
                    )
                }
            }
        }
        .id(tableIdentity)
        .transaction { transaction in
            // 切换来源时不要对数百行做插入/删除动画。
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .animation(nil, value: filtered)
        .scrollIndicators(.visible)
        .contextMenu(forSelectionType: String.self) { ids in
            appContextMenu(for: ids)
        }
        .onChange(of: selection) { _, newValue in
            if store.selectedAppID != newValue {
                store.selectedAppID = newValue
            }
        }
        .onChange(of: store.selectedAppID) { _, newValue in
            if selection != newValue {
                selection = newValue
            }
        }
    }

    /// 应用列表右键菜单：打开、在访达中显示、复制标识。
    @ViewBuilder
    private func appContextMenu(for ids: Set<String>) -> some View {
        let selected = filtered.filter { ids.contains($0.id) }
        let existing = selected.filter { FileManager.default.fileExists(atPath: $0.path) }

        if !selected.isEmpty {
            if selected.count == 1, let app = selected.first, existing.count == 1 {
                Button(L.t("打开应用")) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
                }
            }

            Button(L.t("在访达中显示")) {
                NSWorkspace.shared.activateFileViewerSelecting(
                    existing.map { URL(fileURLWithPath: $0.path) }
                )
            }
            .disabled(existing.isEmpty)

            if selected.count == 1, let app = selected.first, existing.count == 1,
               SwiftLensIntegration.isInstalled {
                Button(L.t("使用 SwiftLens 打开")) {
                    SwiftLensIntegration.open(appPath: app.path, store: store)
                }
            }

            if selected.count == 1, let app = selected.first {
                Divider()

                Button(L.t("复制 Bundle ID")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.displayBundleIdentifier, forType: .string)
                }
                .disabled(app.bundleIdentifier == nil)
            }
        }
    }

    private var tableIdentity: String {
        "\(store.sourceFilter?.rawValue ?? "all")|\(store.platformFilter?.rawValue ?? "all")|\(store.typeFilter.rawValue)|\(String(describing: store.activeSelection))"
    }

    private var hasActiveFilter: Bool {
        store.sourceFilter != nil || store.platformFilter != nil || store.typeFilter != .all
    }
}
