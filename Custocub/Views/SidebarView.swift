import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: CustocubStore

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

                SidebarRow(
                    title: "展示框",
                    symbol: "rectangle.grid.2x2.fill",
                    count: store.galleryItems.count,
                    tint: .purple
                )
                .tag(SidebarSelection.gallery)
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
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
        .padding(.vertical, 3)
    }
}
