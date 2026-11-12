import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: CustocubStore

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
                    tint: .accentColor
                )
                .tag(SidebarSelection.installed)

                if store.ownAppCount > 2 {
                    SidebarRow(
                        title: "开发者的应用",
                        symbol: "chevron.left.forwardslash.chevron.right",
                        count: store.ownAppCount,
                        tint: .purple
                    )
                    .tag(SidebarSelection.own)
                }

                SidebarRow(
                    title: "展示框",
                    symbol: "rectangle.grid.2x2.fill",
                    count: store.galleryItems.count,
                    tint: .purple
                )
                .tag(SidebarSelection.gallery)
            }

            Section("来源") {
                SourceFilterRow(
                    source: nil,
                    title: "全部来源",
                    symbol: "tray.full.fill",
                    color: .accentColor,
                    count: store.installedCount
                )

                ForEach(Self.sourceOrder, id: \.self) { source in
                    if store.sourceCounts[source, default: 0] > 0 {
                        SourceFilterRow(
                            source: source,
                            title: source.title,
                            symbol: source.symbol,
                            color: source.color,
                            count: store.sourceCounts[source, default: 0]
                        )
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
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 18)
                .fixedSize()
                .foregroundStyle(tint)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
                Text("\(snapshot.appCount) 个")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .clipped()
    }
}

private struct SourceFilterRow: View {
    @EnvironmentObject private var store: CustocubStore

    let source: AppSource?
    let title: String
    let symbol: String
    let color: Color
    let count: Int

    private var isSelected: Bool {
        store.sourceFilter == source
    }

    var body: some View {
        Button {
            store.applySourceFilter(source)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .frame(width: 18)
                    .fixedSize()
                    .foregroundStyle(color)
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .clipped()
        }
        .buttonStyle(.plain)
        .selectionDisabled()
        .help(source.map { "只看 \($0.title)" } ?? "清除来源筛选")
    }
}
