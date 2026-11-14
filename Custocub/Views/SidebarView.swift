import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore
    @AppStorage("showDeveloperApps") private var showDeveloperApps = true

    private static let sourceOrder: [AppSource] = [
        .homebrew,
        .appStore,
        .appStoreIOS,
        .steam,
        .jetbrainsToolbox,
        .system,
        .manual
    ]

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("应用") {
                SidebarRow(
                    title: "已安装应用",
                    symbol: "square.grid.2x2.fill",
                    count: store.installedCount,
                    tint: .accentColor,
                    isSelected: store.sidebarSelection == .installed
                )
                .tag(SidebarSelection.installed)

                SidebarRow(
                    title: "展示框",
                    symbol: "rectangle.grid.2x2.fill",
                    count: store.sidebarGalleryCount,
                    tint: .purple,
                    isSelected: store.sidebarSelection == .gallery
                )
                .tag(SidebarSelection.gallery)

            }

            // 功能关闭或未安装时不显示入口，彻底关闭 Homebrew 相关界面。
            if brew.isAvailable {
                Section("Homebrew") {
                    SidebarRow(
                        title: "Homebrew 包",
                        symbol: "mug.fill",
                        count: brew.packageCount,
                        tint: AppSource.homebrew.color,
                        isSelected: store.sidebarSelection == .brew
                    )
                    .tag(SidebarSelection.brew)
                    .help(Text(L.t("独立管理 Formula、Cask 和 Homebrew 快照。")))
                }
            }

            Section("来源") {
                SidebarRow(
                    title: "全部来源",
                    symbol: "tray.full.fill",
                    count: store.installedCount,
                    tint: .accentColor,
                    isSelected: store.sidebarSelection == .source(nil)
                )
                .tag(SidebarSelection.source(nil))

                ForEach(Self.sourceOrder, id: \.self) { source in
                    if source == .system, showDeveloperApps, store.ownAppCount > 2 {
                        SidebarRow(
                            title: "开发者的应用",
                            symbol: "chevron.left.forwardslash.chevron.right",
                            count: store.ownManualCount,
                            tint: .purple,
                            isSelected: store.sidebarSelection == .own
                        )
                        .tag(SidebarSelection.own)
                        .help(Text(L.t("开发者的应用筛选说明")))
                    }

                    if store.sourceCounts[source, default: 0] > 0 {
                        SidebarRow(
                            title: source.title,
                            symbol: source.symbol,
                            count: store.sourceCounts[source, default: 0],
                            tint: source.color,
                            isSelected: store.sidebarSelection == .source(source)
                        )
                        .tag(SidebarSelection.source(source))
                    }
                }
            }

            Section("快照") {
                ForEach(store.snapshots) { snapshot in
                    SnapshotSidebarRow(snapshot: snapshot)
                        .tag(SidebarSelection.snapshot(snapshot.id))
                        .contextMenu {
                            Button("导出快照…") {
                                FileActions.export(snapshot: snapshot, store: store)
                            }
                            Divider()
                            Button("删除快照", role: .destructive) {
                                store.deleteSnapshot(id: snapshot.id)
                            }
                        }
                }

                if store.snapshots.isEmpty {
                    Text("尚未保存快照")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                }
            }

            if store.uninstalledCount > 0 {
                Section("已卸载") {
                    Button {
                        store.sidebarSelection = .gallery
                        store.galleryStatusFilter = .uninstalled
                    } label: {
                        HStack {
                            Label("已卸载的软件", systemImage: "archivebox")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(store.uninstalledCount)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("在展示框中查看历史快照里记录过、当前已卸载的应用")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Custocub")
        .safeAreaInset(edge: .bottom) {
            ScanStatusView()
        }
        .onChange(of: store.sidebarSelection) {
            store.selectedAppID = nil
            store.syncSourceFilterForSelection()
        }
        .onChange(of: brew.isAvailable) { _, available in
            // Homebrew 入口被隐藏时，避免停留在已不可见的页面。
            if !available && store.activeSelection == .brew {
                store.sidebarSelection = .installed
                store.selectedAppID = nil
            }
        }
        .onChange(of: showDeveloperApps) { _, isVisible in
            if !isVisible && store.activeSelection == .own {
                store.sidebarSelection = .installed
                store.selectedAppID = nil
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int
    let tint: Color
    var isSelected = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 18)
                .fixedSize()
                .foregroundStyle(isSelected ? Color.white : tint)
            Text(LocalizedStringKey(title))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .clipped()
    }
}

private struct SnapshotSidebarRow: View {
    let snapshot: AppSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(snapshot.name)
                    .lineLimit(1)
                    .fontWeight(.medium)
            }
            HStack(spacing: 5) {
                Text(snapshot.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(L.t("%d 个", snapshot.appCount))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .clipped()
    }
}
