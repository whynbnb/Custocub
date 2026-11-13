import AppKit
import SwiftUI

struct AppIconView: View {
    let app: AppRecord
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 9

    @State private var image: NSImage?

    init(app: AppRecord, size: CGFloat = 40, cornerRadius: CGFloat = 9) {
        self.app = app
        self.size = size
        self.cornerRadius = cornerRadius
        let cached = IconProvider.shared.cachedIcon(forPath: app.path)
        let stored = app.iconData.flatMap { NSImage(data: $0) }
        _image = State(initialValue: cached ?? stored)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let iconData = app.iconData, let stored = NSImage(data: iconData) {
                Image(nsImage: stored)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .frame(width: size, height: size)
        .task(id: app.path) {
            if image != nil { return }
            if let cached = IconProvider.shared.cachedIcon(forPath: app.path) {
                image = cached
                return
            }
            if let loaded = await IconProvider.shared.iconAsync(forPath: app.path) {
                image = loaded
            } else if let iconData = app.iconData, let stored = NSImage(data: iconData) {
                image = stored
            }
        }
        .onChange(of: app.path) {
            image = IconProvider.shared.cachedIcon(forPath: app.path)
                ?? app.iconData.flatMap { NSImage(data: $0) }
        }
    }
}

struct SourceBadge: View {
    let source: AppSource
    var compact = false

    var body: some View {
        Label(compact ? source.shortTitle : source.title, systemImage: source.symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(source.color)
            .padding(.horizontal, compact ? 6 : 8)
            .frame(height: 22)
            .background(source.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct PlatformBadge: View {
    let platform: AppPlatform

    var body: some View {
        Label(platform.shortTitle, systemImage: platform.symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(platform.color)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(platform.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .help(Text(platform == .universal ? L.t("通用二进制：arm64 + x86_64") : platform.title))
    }
}

struct TypeBadge: View {
    let isSystem: Bool

    var body: some View {
        Text(isSystem ? L.t("系统") : L.t("第三方"))
            .font(.caption.weight(.medium))
            .foregroundStyle(isSystem ? Color.secondary : Color.green)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                (isSystem ? Color.secondary : Color.green).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}

struct GalleryStatusBadge: View {
    let status: GalleryItem.Status

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .installed ? Color.green : Color.red)
            .padding(.horizontal, 8)
            .frame(height: 23)
            .background(
                (status == .installed ? Color.green : Color.red).opacity(0.12),
                in: Capsule()
            )
    }
}

struct OwnAppBadge: View {
    var body: some View {
        Label("开发者的应用", systemImage: "chevron.left.forwardslash.chevron.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(.purple)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey(label))
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct FilterBar: View {
    @EnvironmentObject private var store: CustocubStore
    var showsStatusFilter = false

    private var sourcePickerSelection: Binding<AppSource?> {
        Binding(
            get: { store.sourceFilter },
            set: { newValue in
                store.sourceFilter = newValue

                // 在已安装列表/来源列表中操作时，让侧边栏选择保持同步。
                if store.activeSelection == .installed || store.isSourceSelection {
                    let target = SidebarSelection.source(newValue)
                    if store.sidebarSelection != target {
                        store.sidebarSelection = target
                    }
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索应用、Bundle ID 或路径", text: $store.searchText)
                .textFieldStyle(.plain)

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

            Picker("来源", selection: sourcePickerSelection) {
                Text("全部来源").tag(AppSource?.none)
                ForEach(AppSource.allCases) { source in
                    Label(source.title, systemImage: source.symbol).tag(Optional(source))
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Picker("平台", selection: $store.platformFilter) {
                Text("全部平台").tag(AppPlatform?.none)
                ForEach(AppPlatform.allCases) { platform in
                    Text(platform.title).tag(Optional(platform))
                }
            }
            .labelsHidden()
            .frame(width: 118)

            Picker("类型", selection: $store.typeFilter) {
                ForEach(AppTypeFilter.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 118)

            if showsStatusFilter {
                Picker("状态", selection: $store.galleryStatusFilter) {
                    Text("全部状态").tag(GalleryItem.Status?.none)
                    ForEach(GalleryItem.Status.allCases) { status in
                        Text(status.title).tag(Optional(status))
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            if store.sourceFilter != nil || store.platformFilter != nil
                || store.typeFilter != .all || !store.searchText.isEmpty
                || (showsStatusFilter && store.galleryStatusFilter != nil) {
                Button {
                    store.resetFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除筛选")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }
}

struct ScanStatusView: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        HStack(spacing: 8) {
            if store.isScanning {
                ProgressView().controlSize(.small)
                Text("正在扫描…")
            } else if store.isEnriching {
                ProgressView(
                    value: Double(store.enrichmentDone),
                    total: Double(max(store.enrichmentTotal, 1))
                )
                .controlSize(.small)
                .frame(width: 54)
                Text(L.t("计算体积 %d/%d", store.enrichmentDone, store.enrichmentTotal))
            } else if store.isSavingSnapshot {
                ProgressView().controlSize(.small)
                Text("正在保存快照…")
            } else if !store.statusMessage.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(store.statusMessage)
                    .lineLimit(1)
            } else {
                Image(systemName: "clock")
                Text(store.lastScanAt.map {
                    L.t("上次扫描 %@", $0.formatted(date: .omitted, time: .shortened))
                } ?? L.t("尚未扫描"))
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
