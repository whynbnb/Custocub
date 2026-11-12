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
                    ? "没有匹配个人应用前缀的应用"
                    : (store.hasScanned ? "没有发现应用" : "尚未扫描。点击工具栏的「扫描应用」开始。")
            )
        }
        .navigationTitle(isOwnMode ? "开发者的应用" : "已安装应用")
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
            AppTable(apps: snapshot.apps, emptyMessage: "这个快照中没有符合条件的应用")
        }
        .navigationTitle(snapshot.name)
    }
}

private struct InstalledHeader: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("已安装应用")
                        .font(.title2.weight(.semibold))
                    Text("扫描 /Applications、~/Applications 与系统应用目录，并识别每个应用的来源和架构。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let lastScanAt = store.lastScanAt {
                    Text(lastScanAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
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
                Spacer()
            }
        }
        .padding(16)
        .background(.background)
    }
}

private struct OwnAppsHeader: View {
    @EnvironmentObject private var store: CustocubStore

    private var prefix: String {
        let raw = UserDefaults.standard.string(forKey: "developerBundlePrefix") ?? "me.whynbnb."
        return raw.isEmpty ? "未设置" : raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("开发者的应用")
                        .font(.title2.weight(.semibold))
                    Text("Bundle ID 前缀：\(prefix)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text("\(store.ownAppCount) 个应用")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
                Spacer()
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
                .help(isEditingName ? "完成重命名" : "重命名快照")

                Spacer()

                Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
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
                Spacer()
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
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private enum AppTableColumn {
    static let version: CGFloat = 70
    static let source: CGFloat = 108
    static let platform: CGFloat = 92
    static let type: CGFloat = 58
    static let size: CGFloat = 82
    static let updated: CGFloat = 100
}

private struct AppTable: View {
    @EnvironmentObject private var store: CustocubStore
    let apps: [AppRecord]
    let emptyMessage: String

    @State private var sortField: SortField = .name
    @State private var sortAscending = true

    private enum SortField: String {
        case name = "应用"
        case version = "版本"
        case source = "来源"
        case platform = "平台"
        case type = "类型"
        case size = "大小"
        case updated = "更新"
    }

    private var sortComparator: KeyPathComparator<AppRecord> {
        let order: SortOrder = sortAscending ? .forward : .reverse

        switch sortField {
        case .name:
            return KeyPathComparator(\AppRecord.name, order: order)
        case .version:
            return KeyPathComparator(\AppRecord.versionSortValue, order: order)
        case .source:
            return KeyPathComparator(\AppRecord.sourceSortValue, order: order)
        case .platform:
            return KeyPathComparator(\AppRecord.platformSortValue, order: order)
        case .type:
            return KeyPathComparator(\AppRecord.typeSortValue, order: order)
        case .size:
            return KeyPathComparator(\AppRecord.sizeSortValue, order: order)
        case .updated:
            return KeyPathComparator(\AppRecord.updatedSortValue, order: order)
        }
    }

    private var filtered: [AppRecord] {
        store.filteredApps(apps, sortOrder: [sortComparator])
    }

    var body: some View {
        let items = filtered

        VStack(spacing: 0) {
            header
            Divider()

            if items.isEmpty {
                emptyState
            } else {
                // LazyVStack 只创建可见行，避免从 99 行切到 405 行时一次性布局整张表。
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { app in
                            AppTableRow(
                                app: app,
                                isSelected: store.selectedAppID == app.id
                            )
                            .onTapGesture {
                                store.selectedAppID = app.id
                            }

                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            headerButton("应用", field: .name)
                .frame(minWidth: 180, idealWidth: 280, maxWidth: 360, alignment: .leading)

            headerButton("版本", field: .version, width: AppTableColumn.version)
            headerButton("来源", field: .source, width: AppTableColumn.source)
            headerButton("平台", field: .platform, width: AppTableColumn.platform)
            headerButton("类型", field: .type, width: AppTableColumn.type)
            headerButton("大小", field: .size, width: AppTableColumn.size, alignment: .trailing, trailingPadding: 14, arrowFirst: true)
            headerButton("更新于", field: .updated, width: AppTableColumn.updated)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
    }

    private func headerButton(
        _ title: String,
        field: SortField,
        width: CGFloat? = nil,
        alignment: Alignment = .leading,
        trailingPadding: CGFloat = 0,
        arrowFirst: Bool = false
    ) -> some View {
        Button {
            toggleSort(field)
        } label: {
            HStack(spacing: 3) {
                if arrowFirst, sortField == field {
                    sortIndicator
                }
                Text(title)
                if !arrowFirst, sortField == field {
                    sortIndicator
                }
            }
            .padding(.trailing, trailingPadding)
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(sortField == field ? Color.primary : Color.secondary)
        .help("按\(title)排序")
    }

    private var sortIndicator: some View {
        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
            .font(.system(size: 8, weight: .bold))
    }

    private func toggleSort(_ field: SortField) {
        if sortField == field {
            sortAscending.toggle()
        } else {
            sortField = field
            sortAscending = true
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isScanning && apps.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在扫描应用…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.searchText.isEmpty && !hasActiveFilter {
            ContentUnavailableView(emptyMessage, systemImage: "app.dashed")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "没有符合条件的应用",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("请调整搜索内容或筛选条件。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var hasActiveFilter: Bool {
        store.sourceFilter != nil || store.platformFilter != nil || store.typeFilter != .all
    }
}

private struct AppTableRow: View {
    let app: AppRecord
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                AppIconView(app: app, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .lineLimit(1)
                    Text(app.listSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180, idealWidth: 280, maxWidth: 360, alignment: .leading)

            Text(app.displayVersion)
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .frame(width: AppTableColumn.version, alignment: .leading)

            SourceBadge(source: app.source, compact: true)
                .frame(width: AppTableColumn.source, alignment: .leading)

            PlatformBadge(platform: app.platform)
                .frame(width: AppTableColumn.platform, alignment: .leading)

            TypeBadge(isSystem: app.isSystemApp)
                .frame(width: AppTableColumn.type, alignment: .leading)

            Text(app.displaySize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(app.sizeInBytes == nil ? .secondary : .primary)
                .lineLimit(1)
                .padding(.trailing, 14)
                .frame(width: AppTableColumn.size, alignment: .trailing)

            Text(app.updatedAtListText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: AppTableColumn.updated, alignment: .leading)

            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        .contentShape(Rectangle())
        .help("\(app.name)\n\(app.path)")
    }
}
