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
            ?? app.bundleIdentifier.flatMap { IconProvider.shared.cachedIcon(forBundleID: $0) }
        let stored = app.iconData.flatMap { NSImage(data: $0) }
        _image = State(initialValue: cached ?? stored)
    }

    /// 应用更新后 path 不变，但版本、构建号或更新时间会变化。
    /// 把它作为 task 的 id，让复用中的行重新读取新图标。
    private var iconCacheKey: String {
        let updated = app.updatedAt?.timeIntervalSince1970 ?? 0
        return "\(app.path)|\(app.version ?? "")|\(app.build ?? "")|\(updated)"
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
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: iconCacheKey) {
            if let cached = IconProvider.shared.cachedIcon(forPath: app.path) {
                image = cached
                return
            }
            if let loaded = await IconProvider.shared.iconAsync(forPath: app.path) {
                image = loaded
                return
            }
            // 应用已卸载：先用扫描时缓存的图标，再退回快照里存的那份。
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty,
               let cached = await IconProvider.shared.iconAsync(forBundleID: bundleID) {
                image = cached
                return
            }
            if image == nil, let iconData = app.iconData, let stored = NSImage(data: iconData) {
                image = stored
            }
        }
        .onChange(of: app.path) {
            image = IconProvider.shared.cachedIcon(forPath: app.path)
                ?? app.bundleIdentifier.flatMap { IconProvider.shared.cachedIcon(forBundleID: $0) }
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

struct ManagerBadge: View {
    var body: some View {
        Text(L.t("管理工具"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(height: 17)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .fixedSize()
            .help(Text(L.t("该应用是此来源的管理工具，显示在该分类中，但不重复计数。")))
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
    var minHeight: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight ?? 0, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

struct FilterBar: View {
    @EnvironmentObject private var store: CustocubStore

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

            if store.sourceFilter != nil || store.platformFilter != nil
                || store.typeFilter != .all || !store.searchText.isEmpty {
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

/// 简单的自适应换行布局：子视图按行排列，放不下时自动换到下一行。
///
/// 用于依赖标签、清理项等小胶囊。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let needed = current == 0 ? size.width : current + spacing + size.width
            if needed > maxWidth, current > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rows.count - 1] = needed
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            }
        }

        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: maxWidth.isFinite ? maxWidth : rows.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
