import AppKit
import SwiftUI

extension Notification.Name {
    static let custocubShowCommandPalette = Notification.Name("custocub.showCommandPalette")
}

struct CommandPaletteView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private enum Target {
        case app(GalleryItem)
        case snapshot(AppSnapshot)
        case action(CommandAction)
    }

    private enum CommandAction: String {
        case scan
        case saveSnapshot
        case openHomebrew
        case showGallery
        case showFavorites
        case presentation
    }

    private struct Entry: Identifiable {
        let id: String
        let section: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let target: Target
    }

    private var entries: [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [Entry] = []

        for action in actionEntries {
            if needle.isEmpty || action.searchText.localizedCaseInsensitiveContains(needle) {
                result.append(action.entry)
            }
        }

        for snapshot in store.snapshots {
            if needle.isEmpty || snapshot.name.localizedCaseInsensitiveContains(needle) {
                result.append(Entry(
                    id: "snapshot:\(snapshot.id)",
                    section: L.t("快照"),
                    title: snapshot.name,
                    subtitle: L.t("%d 个应用 · %@", snapshot.appCount, snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)),
                    symbol: "camera",
                    tint: .orange,
                    target: .snapshot(snapshot)
                ))
            }
        }

        let appItems = store.galleryItems.filter { item in
            guard !needle.isEmpty else { return true }
            return item.app.name.localizedCaseInsensitiveContains(needle)
                || item.app.bundleIdentifier?.localizedCaseInsensitiveContains(needle) == true
                || item.app.path.localizedCaseInsensitiveContains(needle)
        }
        .prefix(needle.isEmpty ? 10 : 30)

        for item in appItems {
            result.append(Entry(
                id: "app:\(item.app.id)",
                section: L.t("应用"),
                title: item.app.name,
                subtitle: item.status == .uninstalled
                    ? L.t("已卸载 · 最后出现于 %@", item.snapshotName ?? L.t("未知"))
                    : item.app.displayBundleIdentifier,
                symbol: "app",
                tint: item.app.source.color,
                target: .app(item)
            ))
        }

        return result
    }

    private var actionEntries: [(searchText: String, entry: Entry)] {
        [
            (
                "扫描 scan refresh 应用 scan apps",
                Entry(
                    id: "action:scan",
                    section: L.t("操作"),
                    title: L.t("扫描应用"),
                    subtitle: L.t("重新扫描这台 Mac 上的应用"),
                    symbol: "arrow.clockwise",
                    tint: .accentColor,
                    target: .action(.scan)
                )
            ),
            (
                "保存快照 snapshot save",
                Entry(
                    id: "action:snapshot",
                    section: L.t("操作"),
                    title: L.t("保存快照"),
                    subtitle: L.t("把当前应用清单保存为历史快照"),
                    symbol: "camera.fill",
                    tint: .purple,
                    target: .action(.saveSnapshot)
                )
            ),
            (
                "homebrew brew 包 packages",
                Entry(
                    id: "action:brew",
                    section: L.t("操作"),
                    title: L.t("打开 Homebrew"),
                    subtitle: L.t("进入 Homebrew 包管理"),
                    symbol: "mug.fill",
                    tint: AppSource.homebrew.color,
                    target: .action(.openHomebrew)
                )
            ),
            (
                "展示框 gallery 收藏柜",
                Entry(
                    id: "action:gallery",
                    section: L.t("操作"),
                    title: L.t("展示框"),
                    subtitle: L.t("浏览全部应用与历史快照"),
                    symbol: "photo.stack.fill",
                    tint: .purple,
                    target: .action(.showGallery)
                )
            ),
            (
                "收藏 favorites star",
                Entry(
                    id: "action:favorites",
                    section: L.t("操作"),
                    title: L.t("收藏"),
                    subtitle: L.t("查看收藏的应用"),
                    symbol: "star.fill",
                    tint: .yellow,
                    target: .action(.showFavorites)
                )
            ),
            (
                "展示模式 presentation fullscreen 全屏",
                Entry(
                    id: "action:presentation",
                    section: L.t("操作"),
                    title: L.t("展示模式"),
                    subtitle: L.t("在独立窗口中展示图标墙"),
                    symbol: "rectangle.inset.filled",
                    tint: .teal,
                    target: .action(.presentation)
                )
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            results
            Divider()
            footer
        }
        .frame(width: 680, height: 520)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用、快照或操作", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(runSelected)
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    @ViewBuilder
    private var results: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "没有匹配的结果",
                systemImage: "magnifyingglass",
                description: Text("试试应用名称、Bundle ID、快照名称或操作。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index == 0 || entries[index - 1].section != entry.section {
                                Text(entry.section)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                            }

                            resultRow(entry, isSelected: index == selectedIndex)
                                .id(entry.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    run(entry)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: selectedIndex) { _, index in
                    guard entries.indices.contains(index) else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(entries[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func resultRow(_ entry: Entry, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            icon(for: entry)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func icon(for entry: Entry) -> some View {
        if case .app(let item) = entry.target {
            AppIconView(app: item.app, size: 30, cornerRadius: 7)
        } else {
            Image(systemName: entry.symbol)
                .font(.system(size: 15))
                .foregroundStyle(entry.tint)
                .frame(width: 30, height: 30)
                .background(entry.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↑↓ 选择")
            Text("↵ 执行")
            Text("esc 关闭")
            Spacer()
            Text("⌘K")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + entries.count) % entries.count
    }

    private func runSelected() {
        guard entries.indices.contains(selectedIndex) else { return }
        run(entries[selectedIndex])
    }

    private func run(_ entry: Entry) {
        switch entry.target {
        case .app(let item):
            store.resetFilters()
            store.gallerySnapshotID = nil
            store.sidebarSelection = item.status == .installed ? .installed : .gallery
            store.selectedAppID = item.app.id

        case .snapshot(let snapshot):
            store.resetFilters()
            store.selectedAppID = nil
            store.sidebarSelection = .snapshot(snapshot.id)

        case .action(let action):
            switch action {
            case .scan:
                Task { await store.refresh(ignoreRecentScan: true) }
            case .saveSnapshot:
                Task { await store.saveSnapshot() }
            case .openHomebrew:
                store.selectedAppID = nil
                store.sidebarSelection = .brew
                Task { await brew.load() }
            case .showGallery:
                store.selectedAppID = nil
                store.sidebarSelection = .gallery
            case .showFavorites:
                store.selectedAppID = nil
                store.sidebarSelection = .favorites
            case .presentation:
                openWindow(id: GalleryPresentation.windowID)
            }
        }

        dismiss()
    }
}
