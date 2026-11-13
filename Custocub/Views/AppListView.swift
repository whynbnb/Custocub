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

struct SnapshotAppsView: View {
    @EnvironmentObject private var store: CustocubStore
    let snapshot: AppSnapshot

    var body: some View {
        VStack(spacing: 0) {
            SnapshotHeaderView(snapshot: snapshot)
            Divider()
            FilterBar()
            Divider()
            AppTable(apps: snapshot.apps, emptyMessage: L.t("这个快照中没有符合条件的应用"))
        }
        .navigationTitle(snapshot.name)
    }
}

private struct InstalledHeader: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text("已安装应用")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("扫描 /Applications、~/Applications 与系统应用目录，并识别每个应用的来源和架构。")
                        .accessibilityLabel("扫描说明")
                }
                Spacer()
                if let lastScanAt = store.lastScanAt {
                    Text(lastScanAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            MetricChipRow {
                MetricChip(title: "应用", value: "\(store.installedCount)", symbol: "square.grid.2x2", color: .accentColor)
                MetricChip(title: "系统", value: "\(store.systemCount)", symbol: "apple.logo", color: .secondary)
                MetricChip(title: "第三方", value: "\(store.thirdPartyCount)", symbol: "shippingbox", color: .green)
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

                Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            MetricChipRow {
                MetricChip(title: "应用", value: "\(snapshot.appCount)", symbol: "square.grid.2x2", color: .accentColor)
                MetricChip(title: "系统", value: "\(snapshot.systemCount)", symbol: "apple.logo", color: .secondary)
                MetricChip(title: "第三方", value: "\(snapshot.thirdPartyCount)", symbol: "shippingbox", color: .green)
                MetricChip(title: "App Store", value: "\(snapshot.appStoreCount)", symbol: "bag", color: .blue)
                MetricChip(title: "Homebrew", value: "\(snapshot.homebrewCount)", symbol: "mug", color: .orange)
                if snapshot.sourceCounts[.steam, default: 0] > 0 {
                    MetricChip(title: "Steam", value: "\(snapshot.sourceCounts[.steam, default: 0])", symbol: "gamecontroller", color: AppSource.steam.color)
                }
                if snapshot.sourceCounts[.jetbrainsToolbox, default: 0] > 0 {
                    MetricChip(title: "Toolbox", value: "\(snapshot.sourceCounts[.jetbrainsToolbox, default: 0])", symbol: "wrench.and.screwdriver", color: AppSource.jetbrainsToolbox.color)
                }
                MetricChip(title: "占用", value: snapshot.totalSizeText, symbol: "internaldrive", color: .purple)
            }

            HStack(spacing: 14) {
                Label(snapshot.hostName, systemImage: "desktopcomputer")
                Label(snapshot.osVersion, systemImage: "apple.logo")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                TextField("为这个快照添加备注…", text: $noteDraft)
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
                    .onSubmit(commitNote)
                if noteFocused {
                    Button("保存备注", action: commitNote)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(LocalizedStringKey(title))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize(horizontal: true, vertical: false)
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

    private var tableIdentity: String {
        "\(store.sourceFilter?.rawValue ?? "all")|\(store.platformFilter?.rawValue ?? "all")|\(store.typeFilter.rawValue)|\(String(describing: store.activeSelection))"
    }

    private var hasActiveFilter: Bool {
        store.sourceFilter != nil || store.platformFilter != nil || store.typeFilter != .all
    }
}
