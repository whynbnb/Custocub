import AppKit
import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var store: CustocubStore

    @State private var iconHistoryApp: AppRecord?

    private let columns = [
        GridItem(.adaptive(minimum: 172, maximum: 230), spacing: 14)
    ]

    var body: some View {
        Group {
            if store.hasScanned {
                VStack(spacing: 0) {
                    header
                    Divider()
                    FilterBar(showsStatusFilter: true)
                    Divider()

                    let items = store.filteredGalleryItems(store.galleryItems)

                    if items.isEmpty {
                        ContentUnavailableView(
                            store.galleryItems.isEmpty ? L.t("展示框还是空的") : L.t("没有符合条件的应用"),
                            systemImage: store.galleryItems.isEmpty ? "rectangle.grid.2x2" : "line.3.horizontal.decrease.circle",
                            description: Text(store.galleryItems.isEmpty
                                ? L.t("保存一个快照后，这里会像收藏柜一样展示软件；已卸载的软件也会被保留。")
                                : L.t("请调整搜索内容或筛选条件。"))
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                MetricChip(
                    title: "已安装",
                    value: "\(store.galleryItems.count { $0.status == .installed })",
                    symbol: "checkmark.circle",
                    color: .green
                )
                MetricChip(
                    title: "已卸载",
                    value: "\(store.uninstalledCount)",
                    symbol: "archivebox",
                    color: .red
                )
                MetricChip(
                    title: "系统",
                    value: "\(store.galleryItems.count { $0.app.isSystemApp })",
                    symbol: "apple.logo",
                    color: .secondary
                )
                MetricChip(
                    title: "第三方",
                    value: "\(store.galleryItems.count { !$0.app.isSystemApp })",
                    symbol: "shippingbox",
                    color: .green
                )
                Spacer()
                if store.uninstalledCount > 0 {
                    Text("已卸载条目来自历史快照")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .background(.background)
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
