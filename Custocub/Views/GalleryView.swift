import AppKit
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var store: CustocubStore

    @State private var iconHistoryApp: AppRecord?
    @State private var appStoryApp: AppRecord?

    private let columns = [
        GridItem(.adaptive(minimum: 172, maximum: 230), spacing: 14)
    ]

    var body: some View {
        Group {
            if store.hasScanned {
                VStack(spacing: 0) {
                    header
                    Divider()
                    galleryTimeline
                    Divider()

                    let baseItems = store.galleryDisplayItems
                    let items = store.filteredGalleryItems(baseItems)

                    GalleryFilterBar(
                        visibleCount: items.count,
                        totalCount: baseItems.count
                    )
                    Divider()

                    if items.isEmpty {
                        ContentUnavailableView(
                            emptyTitle(baseItems: baseItems),
                            systemImage: baseItems.isEmpty
                                ? "rectangle.grid.2x2"
                                : "line.3.horizontal.decrease.circle",
                            description: Text(emptyDescription(baseItems: baseItems))
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(items) { item in
                                    GalleryCard(
                                        item: item,
                                        isSelected: store.selectedAppID == item.app.id,
                                        isManager: store.isManagerNode(item.app),
                                        hasIconHistory: store.hasIconHistory(for: item.app),
                                        onShowIconHistory: { iconHistoryApp = item.app }
                                    )
                                    .onTapGesture {
                                        store.selectedAppID = item.app.id
                                    }
                                    .contextMenu {
                                        cardContextMenu(for: item)
                                    }
                                }
                            }
                            .padding(18)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "正在准备展示框",
                    systemImage: "rectangle.grid.2x2",
                    description: Text("先扫描这台 Mac 上的应用，才能区分「已安装」与「已卸载」。")
                )
            }
        }
        .navigationTitle("展示框")
        .sheet(item: $iconHistoryApp) { app in
            IconHistorySheet(app: app)
                .environmentObject(store)
        }
        .sheet(item: $appStoryApp) { app in
            AppStorySheet(app: app)
                .environmentObject(store)
        }
    }

    private var header: some View {
        let items = store.galleryDisplayItems
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text("展示框")
                        .font(.title2.weight(.semibold))
                    Image(systemName: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("像收藏柜一样浏览所有软件，包括已经卸载、但仍保存在历史快照中的应用。")
                        .accessibilityLabel("展示框说明")
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    toggleStatus(.installed)
                } label: {
                    MetricChip(
                        title: "已安装",
                        value: "\(items.count { $0.status == .installed })",
                        symbol: "checkmark.circle",
                        color: .green,
                        isActive: store.galleryStatusFilters.contains(.installed)
                    )
                }
                .buttonStyle(.plain)
                .help(Text(L.t("点击筛选")))

                Button {
                    toggleStatus(.uninstalled)
                } label: {
                    MetricChip(
                        title: "已卸载",
                        value: "\(items.count { $0.status == .uninstalled })",
                        symbol: "archivebox",
                        color: .red,
                        isActive: store.galleryStatusFilters.contains(.uninstalled)
                    )
                }
                .buttonStyle(.plain)
                .help(Text(L.t("点击筛选")))

                Button {
                    toggleType(.system)
                } label: {
                    MetricChip(
                        title: "系统",
                        value: "\(items.count { $0.app.isSystemApp })",
                        symbol: "apple.logo",
                        color: .secondary,
                        isActive: store.galleryTypeFilters.contains(.system)
                    )
                }
                .buttonStyle(.plain)
                .help(Text(L.t("点击筛选")))

                Button {
                    toggleType(.thirdParty)
                } label: {
                    MetricChip(
                        title: "第三方",
                        value: "\(items.count { !$0.app.isSystemApp })",
                        symbol: "shippingbox",
                        color: .green,
                        isActive: store.galleryTypeFilters.contains(.thirdParty)
                    )
                }
                .buttonStyle(.plain)
                .help(Text(L.t("点击筛选")))

                Spacer()
                if let snapshot = store.gallerySnapshot {
                    Text(L.t("正在查看快照「%@」", snapshot.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if items.contains(where: { $0.status == .uninstalled }) {
                    Text("已卸载条目来自历史快照")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(.background)
    }

    private var galleryTimeline: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)

            Text("快照时间轴")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    timelineNode(
                        title: L.t("今天"),
                        count: store.apps.count,
                        snapshotID: nil,
                        symbol: "sparkles"
                    )

                    ForEach(store.snapshots) { snapshot in
                        timelineNode(
                            title: snapshot.name,
                            count: snapshot.apps.count,
                            snapshotID: snapshot.id,
                            symbol: "camera"
                        )
                    }
                }
                .padding(.vertical, 1)
            }

            if store.snapshots.isEmpty {
                Text(L.t("保存快照后可回看历史"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }

            if store.gallerySnapshotID != nil {
                Button(L.t("回到今天")) {
                    store.gallerySnapshotID = nil
                    store.selectedAppID = nil
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.bar)
    }

    private func timelineNode(
        title: String,
        count: Int,
        snapshotID: UUID?,
        symbol: String
    ) -> some View {
        let isSelected = store.gallerySnapshotID == snapshotID

        return Button {
            store.gallerySnapshotID = snapshotID
            store.selectedAppID = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(L.t("%d 个应用", count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func emptyTitle(baseItems: [GalleryItem]) -> String {
        if baseItems.isEmpty {
            return store.gallerySnapshot != nil ? L.t("这个快照没有应用") : L.t("展示框还是空的")
        }
        return L.t("没有符合条件的应用")
    }

    private func emptyDescription(baseItems: [GalleryItem]) -> String {
        if !baseItems.isEmpty {
            return L.t("请调整搜索内容或筛选条件。")
        }
        if store.gallerySnapshot != nil {
            return L.t("这个快照没有记录任何应用。")
        }
        return L.t("保存一个快照后，这里会像收藏柜一样展示软件；已卸载的软件也会被保留。")
    }

    private func toggleStatus(_ status: GalleryItem.Status) {
        if store.galleryStatusFilters.contains(status) {
            store.galleryStatusFilters.remove(status)
        } else {
            store.galleryStatusFilters.insert(status)
        }
    }

    private func toggleType(_ type: AppTypeFilter) {
        if store.galleryTypeFilters.contains(type) {
            store.galleryTypeFilters.remove(type)
        } else {
            store.galleryTypeFilters.insert(type)
        }
    }

    @ViewBuilder
    private func cardContextMenu(for item: GalleryItem) -> some View {
        let app = item.app

        if item.status == .installed {
            Button("打开应用") {
                NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
            }
        }

        Button("在访达中显示") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
        }
        .disabled(!FileManager.default.fileExists(atPath: app.path))

        if SwiftLensIntegration.isInstalled, FileManager.default.fileExists(atPath: app.path) {
            Button(L.t("使用 SwiftLens 打开")) {
                SwiftLensIntegration.open(appPath: app.path, store: store)
            }
        }

        Button(L.t("查看图标历史…")) {
            iconHistoryApp = app
        }

        Button(L.t("查看应用档案…")) {
            appStoryApp = app
        }

        Button("复制 Bundle ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.displayBundleIdentifier, forType: .string)
        }
        .disabled(app.bundleIdentifier == nil)

        if let snapshotName = item.snapshotName {
            Divider()
            Text(L.t("最后出现于快照：%@", snapshotName))
        }
    }
}

private struct GalleryCard: View {
    let item: GalleryItem
    let isSelected: Bool
    var isManager = false
    var hasIconHistory = false
    var onShowIconHistory: (() -> Void)? = nil

    private var app: AppRecord { item.app }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                GalleryStatusBadge(status: item.status)
                if isManager {
                    ManagerBadge()
                }
                Spacer(minLength: 0)
                if hasIconHistory, let onShowIconHistory {
                    Button(action: onShowIconHistory) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(Text(L.t("查看图标历史")))
                }
                PlatformBadge(platform: app.platform)
            }

            HStack {
                Spacer()
                AppIconView(app: app, size: 66, cornerRadius: 15)
                Spacer()
            }

            VStack(spacing: 3) {
                Text(app.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(L.t("版本 %@", app.displayVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 5) {
                SourceBadge(source: app.source, compact: true)
                Spacer(minLength: 0)
                Text(app.displaySize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let lastSeenAt = item.lastSeenAt, item.status == .uninstalled {
                Text(L.t("最后出现于 %@", lastSeenAt.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(app.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(app.path)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .opacity(item.status == .uninstalled ? 0.92 : 1)
        .help("\(app.name)\n\(app.path)")
    }
}

// MARK: - 展示框筛选

private struct GalleryFilterBar: View {
    @EnvironmentObject private var store: CustocubStore
    let visibleCount: Int
    let totalCount: Int

    private var hasActiveFilters: Bool {
        !store.searchText.isEmpty
            || !store.gallerySourceFilters.isEmpty
            || !store.galleryPlatformFilters.isEmpty
            || !store.galleryTypeFilters.isEmpty
            || !store.galleryStatusFilters.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索应用、Bundle ID 或路径", text: $store.searchText)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除搜索")
            }

            Divider().frame(height: 18)

            MultiSelectFilterButton(
                allTitle: "全部来源",
                width: 150,
                options: AppSource.allCases.map {
                    MultiSelectOption(value: $0, title: $0.title, symbol: $0.symbol)
                },
                selection: $store.gallerySourceFilters
            )

            MultiSelectFilterButton(
                allTitle: "全部平台",
                width: 118,
                options: AppPlatform.allCases.map {
                    MultiSelectOption(value: $0, title: $0.title, symbol: $0.symbol)
                },
                selection: $store.galleryPlatformFilters
            )

            MultiSelectFilterButton(
                allTitle: "全部类型",
                width: 112,
                options: [
                    MultiSelectOption(value: AppTypeFilter.system, title: AppTypeFilter.system.title, symbol: "apple.logo"),
                    MultiSelectOption(value: AppTypeFilter.thirdParty, title: AppTypeFilter.thirdParty.title, symbol: "shippingbox")
                ],
                selection: $store.galleryTypeFilters
            )

            MultiSelectFilterButton(
                allTitle: "全部状态",
                width: 112,
                options: GalleryItem.Status.allCases.map {
                    MultiSelectOption(value: $0, title: $0.title, symbol: $0.symbol)
                },
                selection: $store.galleryStatusFilters
            )

            if hasActiveFilters {
                Button {
                    store.resetFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除筛选")
            }

            Text(L.t("显示 %d / %d", visibleCount, totalCount))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }
}

private struct MultiSelectOption<Option: Hashable & Identifiable>: Identifiable {
    let value: Option
    let title: String
    let symbol: String?

    var id: Option.ID { value.id }
}

private struct MultiSelectFilterButton<Option: Hashable & Identifiable>: View {
    let allTitle: String
    let width: CGFloat
    let options: [MultiSelectOption<Option>]
    @Binding var selection: Set<Option>

    @State private var showing = false

    private var labelText: String {
        if selection.isEmpty || selection.count == options.count {
            return L.t(allTitle)
        }
        if selection.count == 1,
           let option = options.first(where: { selection.contains($0.value) }) {
            return option.title
        }
        return L.t("已选 %d 项", selection.count)
    }

    private var isActive: Bool {
        !selection.isEmpty && selection.count < options.count
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 5) {
                Text(labelText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(width: width, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                filterRow(
                    title: L.t(allTitle),
                    selected: selection.isEmpty,
                    symbol: nil
                ) {
                    selection.removeAll()
                }

                Divider()
                    .padding(.vertical, 3)

                ForEach(options) { option in
                    filterRow(
                        title: option.title,
                        selected: selection.contains(option.value),
                        symbol: option.symbol
                    ) {
                        if selection.contains(option.value) {
                            selection.remove(option.value)
                        } else {
                            selection.insert(option.value)
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: 230)
        }
    }

    private func filterRow(
        title: String,
        selected: Bool,
        symbol: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .opacity(selected ? 1 : 0)
                    .frame(width: 12)
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}
