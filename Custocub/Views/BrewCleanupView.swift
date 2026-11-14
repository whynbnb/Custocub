import AppKit
import SwiftUI

/// Homebrew 清理界面：缓存分布、旧版本、无用依赖、缺失依赖与各种清理操作。
struct BrewCleanupView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var confirmAction: CleanupAction?
    @State private var expandedCache = false
    @State private var showsTerminal = false

    /// 需要二次确认的清理操作。
    enum CleanupAction: Identifiable {
        case standard
        case all
        case everything
        case autoremove
        case prunePrefix

        var id: String { title }

        var title: String {
            switch self {
            case .standard: L.t("清理缓存与旧版本")
            case .all: L.t("清理全部缓存")
            case .everything: L.t("清空下载缓存")
            case .autoremove: L.t("移除不再需要的依赖")
            case .prunePrefix: L.t("修复安装前缀链接")
            }
        }

        var message: String {
            switch self {
            case .standard:
                L.t("会移除过期下载、旧版本、残留锁文件和日志，并自动移除无用的依赖。已安装的最新版本不受影响。")
            case .all:
                L.t("会删除全部下载缓存（包括当前最新版本），不会卸载任何已安装的包。下次安装或升级时会重新下载。")
            case .everything:
                L.t("会连同可清理的临时文件和 Ruby 缓存一起清空，通常能释放最多空间。已安装的包不受影响。")
            case .autoremove:
                L.t("会卸载「只作为依赖安装、且已不再被任何包需要」的 formula。仍被依赖的包会被 Homebrew 保留。")
            case .prunePrefix:
                L.t("只清理安装前缀中失效的符号链接和空目录，不会删除任何已安装的包。")
            }
        }

        var isDestructive: Bool {
            switch self {
            case .standard, .autoremove: true
            case .all, .everything, .prunePrefix: false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !brew.isAvailable {
                ContentUnavailableView(
                    L.t("Homebrew 功能当前不可用"),
                    systemImage: "mug",
                    description: Text(L.t("开启 Homebrew 功能后才能清理缓存和依赖。"))
                )
            } else if brew.cleanupReport == nil && brew.isAnalyzingCleanup {
                analyzingView
            } else if let report = brew.cleanupReport {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        overviewCards(report)
                        actionsSection(report)
                        cacheSection(report)
                        oldVersionsSection(report)
                        unneededSection(report)
                        healthSection(report)
                    }
                    .padding(16)
                }
            } else {
                emptyView
            }
        }
        .navigationTitle("Homebrew 清理")
        .task {
            await brew.analyzeCleanup()
        }
        .confirmationDialog(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = confirmAction {
                Button(action.title, role: action.isDestructive ? .destructive : nil) {
                    let target = action
                    confirmAction = nil
                    Task { await perform(target) }
                }
            }
            Button(L.t("取消"), role: .cancel) { confirmAction = nil }
        } message: {
            Text(confirmAction?.message ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if brew.isAnalyzingCleanup {
                ProgressView().controlSize(.small)
                Text(L.t("正在分析…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await brew.analyzeCleanup(force: true) }
            } label: {
                Label(L.t("重新分析"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(brew.isAnalyzingCleanup || brew.isRunningCommand)

            Button {
                Task { await brew.cleanupDryRun() }
            } label: {
                Label(L.t("预览清理"), systemImage: "eye")
            }
            .controlSize(.small)
            .disabled(brew.isRunningCommand)

            Button {
                showsTerminal = true
            } label: {
                Label(L.t("命令日志"), systemImage: "terminal")
            }
            .controlSize(.small)

            Spacer()

            if let freed = brew.lastCleanupFreedBytes, freed > 0 {
                Label(L.t("上次释放约 %@", freed.formatted(.byteCount(style: .file))), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
        }
        // 固定高度，切换分区时不影响下方布局。
        .frame(height: 40)
        .padding(.horizontal, 16)
        .background(.bar)
        .sheet(isPresented: $showsTerminal) {
            BrewConsoleView()
                .environmentObject(brew)
        }
    }

    private var analyzingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L.t("正在分析缓存与依赖，可能需要几秒…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            L.t("还没有分析结果"),
            systemImage: "sparkles",
            description: Text(L.t("点击「重新分析」查看可清理的缓存、旧版本和无用依赖。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overview

    private func overviewCards(_ report: BrewCleanupReport) -> some View {
        // 用自适应网格代替横向滚动，避免卡片被裁掉。
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 10)],
            alignment: .leading,
            spacing: 10
        ) {
            CleanupMetricCard(
                title: L.t("可释放"),
                value: standardFreeBytes(report).formatted(.byteCount(style: .file)),
                detail: report.pendingCleanupCount > 0
                    ? L.t("%d 个条目", report.pendingCleanupCount)
                    : L.t("无待清理条目"),
                symbol: "internaldrive",
                color: report.pendingCleanupCount > 0 ? .purple : .secondary
            )
            CleanupMetricCard(
                title: L.t("深度清理"),
                value: (report.deepCleanFreeBytes ?? report.cacheBytes).formatted(.byteCount(style: .file)),
                detail: L.t("含全部下载缓存"),
                symbol: "trash.slash",
                color: .orange
            )
            CleanupMetricCard(
                title: L.t("缓存占用"),
                value: report.cacheBytes.formatted(.byteCount(style: .file)),
                detail: L.t("下载 %@", (report.cacheCategories.first { $0.isDownload }?.bytes ?? 0)
                    .formatted(.byteCount(style: .file))),
                symbol: "archivebox",
                color: .orange
            )
            CleanupMetricCard(
                title: L.t("无用依赖"),
                value: "\(report.unneededFormulae.count)",
                detail: report.unneededFormulae.isEmpty ? L.t("没有可移除项") : L.t("可 autoremove"),
                symbol: "link.badge.plus",
                color: report.unneededFormulae.isEmpty ? .secondary : .red
            )
            CleanupMetricCard(
                title: L.t("旧版本"),
                value: "\(report.oldVersions.count)",
                detail: report.oldVersions.isEmpty ? L.t("每个包只有一个版本") : L.t("可清理旧 keg"),
                symbol: "clock.arrow.circlepath",
                color: report.oldVersions.isEmpty ? .secondary : .blue
            )
            CleanupMetricCard(
                title: L.t("已安装体积"),
                value: report.cellarBytes.formatted(.byteCount(style: .file)),
                detail: L.t("Formula %d · 依赖 %d", report.leavesCount, report.dependencyCount),
                symbol: "shippingbox",
                color: .green
            )
        }
    }

    /// 标准清理的可释放空间。没有待清理条目时不能拿缓存总量充数。
    private func standardFreeBytes(_ report: BrewCleanupReport) -> Int64 {
        if let estimated = report.estimatedFreeBytes { return estimated }
        return report.pendingCleanupCount > 0 ? report.cacheBytes : 0
    }

    // MARK: - Actions

    private func actionsSection(_ report: BrewCleanupReport) -> some View {
        SectionCard(title: "清理操作") {
            VStack(spacing: 10) {
                CleanupActionRow(
                    title: L.t("标准清理"),
                    command: "brew cleanup",
                    description: L.t("移除过期下载、旧版本、残留锁文件与日志，并自动移除无用依赖。"),
                    symbol: "trash",
                    color: .accentColor
                ) {
                    confirmAction = .standard
                }

                Divider()

                CleanupActionRow(
                    title: L.t("移除无用依赖"),
                    command: "brew autoremove",
                    description: report.unneededFormulae.isEmpty
                        ? L.t("当前没有只作为依赖安装、且不再被需要的包。")
                        : L.t("将移除 %@", report.unneededFormulae.prefix(6).joined(separator: "、")
                            + (report.unneededFormulae.count > 6 ? "…" : "")),
                    symbol: "link.badge.plus",
                    color: .red,
                    enabled: !report.unneededFormulae.isEmpty
                ) {
                    confirmAction = .autoremove
                }

                Divider()

                CleanupActionRow(
                    title: L.t("清理全部缓存"),
                    command: "brew cleanup --prune=all",
                    description: L.t("删除所有下载缓存（含最新版本），保留已安装的包。"),
                    symbol: "archivebox",
                    color: .orange
                ) {
                    confirmAction = .all
                }

                Divider()

                CleanupActionRow(
                    title: L.t("清空下载缓存"),
                    command: "brew cleanup --prune=all --scrub",
                    description: L.t("连 Ruby 缓存与临时文件一并清理，通常释放最多空间。"),
                    symbol: "trash.slash",
                    color: .purple
                ) {
                    confirmAction = .everything
                }

                Divider()

                CleanupActionRow(
                    title: L.t("修复安装前缀链接"),
                    command: "brew cleanup --prune-prefix",
                    description: L.t("只清理失效的符号链接和空目录，不删除已安装的包。"),
                    symbol: "wrench.and.screwdriver",
                    color: .teal
                ) {
                    confirmAction = .prunePrefix
                }
            }
        }
    }

    // MARK: - Cache

    private func cacheSection(_ report: BrewCleanupReport) -> some View {
        SectionCard(title: "缓存占用") {
            VStack(spacing: 8) {
                ForEach(report.cacheCategories.prefix(expandedCache ? report.cacheCategories.count : 4)) { category in
                    CleanupBarRow(
                        title: category.name,
                        detail: category.itemCount.map { L.t("%d 项", $0) },
                        bytes: category.bytes,
                        total: report.cacheBytes,
                        color: category.isDownload ? .orange : .secondary
                    )
                }

                if report.cacheCategories.count > 4 {
                    Button(expandedCache ? L.t("收起") : L.t("显示全部")) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expandedCache.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 6) {
                    Label(report.cachePath, systemImage: "folder")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button(L.t("在访达中显示")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: report.cachePath))
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Old versions

    private func oldVersionsSection(_ report: BrewCleanupReport) -> some View {
        SectionCard(title: "旧版本") {
            if report.oldVersions.isEmpty {
                Text(L.t("每个已安装的 formula 都只有一个版本，没有旧 keg 需要清理。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.oldVersions) { item in
                        HStack(spacing: 8) {
                            Text(item.formula)
                                .font(.callout.monospaced())
                            Spacer()
                            Text(item.versions.joined(separator: " → "))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let package = brew.packages.first(where: {
                                $0.kind == .formula && $0.name == item.formula
                            }) {
                                Button(L.t("清理")) {
                                    Task { await brew.cleanupPackage(package) }
                                }
                                .controlSize(.mini)
                            }
                        }
                    }

                    Text(L.t("「brew cleanup」会保留最新版本，只删除更早的 keg。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Unneeded dependencies

    private func unneededSection(_ report: BrewCleanupReport) -> some View {
        SectionCard(title: "无用依赖") {
            if report.unneededFormulae.isEmpty {
                Text(L.t("没有「只作为依赖安装、且不再被需要」的 formula。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("%d 个 formula 可以安全移除：", report.unneededFormulae.count))
                        .font(.callout)

                    FlowLayout(spacing: 6) {
                        ForEach(report.unneededFormulae, id: \.self) { name in
                            Text(name)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 7)
                                .frame(height: 20)
                                .background(Color.red.opacity(0.1), in: Capsule())
                                .foregroundStyle(.red)
                        }
                    }

                    Text(L.t("Homebrew 会自动保留仍被其他包依赖的 formula，以及被固定（pinned）的包。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Health

    private func healthSection(_ report: BrewCleanupReport) -> some View {
        SectionCard(title: "健康检查") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: report.missingDependencies.isEmpty
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.missingDependencies.isEmpty ? .green : .orange)
                    Text(report.missingDependencies.isEmpty
                        ? L.t("已安装的包依赖完整")
                        : L.t("有 %d 个包存在缺失依赖", report.missingDependencies.count))
                        .font(.callout)
                    Spacer()
                    Button(L.t("运行 brew missing")) {
                        Task { await brew.checkMissing() }
                    }
                    .controlSize(.small)
                    .disabled(brew.isRunningCommand)
                }

                if !report.missingDependencies.isEmpty {
                    ForEach(report.missingDependencies, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text(L.t("日志目录"))
                        .font(.callout)
                    Text(report.logsPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(report.logsBytes.formatted(.byteCount(style: .file)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func perform(_ action: CleanupAction) async {
        switch action {
        case .standard: await brew.cleanupStandard()
        case .all: await brew.cleanupAll()
        case .everything: await brew.cleanupEverything()
        case .autoremove: await brew.autoremove()
        case .prunePrefix: await brew.prunePrefix()
        }
    }
}

// MARK: - Components

private struct CleanupMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption)

            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct CleanupActionRow: View {
    @EnvironmentObject private var brew: BrewStore

    let title: String
    let command: String
    let description: String
    let symbol: String
    let color: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(enabled ? color : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(L.t("执行"), action: action)
                .controlSize(.small)
                .disabled(!enabled || brew.isRunningCommand)
        }
    }
}

private struct CleanupBarRow: View {
    let title: String
    let detail: String?
    let bytes: Int64
    let total: Int64
    let color: Color

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(bytes) / Double(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(bytes.formatted(.byteCount(style: .file)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(color.opacity(0.75))
                        .frame(width: max(2, geometry.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

/// 简单的自适应换行布局，用于显示依赖名标签。
private struct FlowLayout: Layout {
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
