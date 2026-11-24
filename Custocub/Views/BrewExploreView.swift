import AppKit
import SwiftUI

/// Homebrew 探索：列出仓库里**所有**可安装的 Formula 与 Cask。
///
/// 与「包」分区的区别：
/// - 「包」只显示本机已安装的包；
/// - 「探索」显示整个 Homebrew 仓库，可按下载量浏览与搜索，
///   数据直接来自 formulae.brew.sh 的官方接口。
struct BrewExploreView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var showsTerminal = false
    @State private var confirmInstall: BrewCatalogEntry?
    @State private var confirmNameInstall: String?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if !brew.isAvailable {
                ContentUnavailableView(
                    L.t("Homebrew 功能当前不可用"),
                    systemImage: "safari",
                    description: Text(L.t("开启 Homebrew 功能后才能浏览和安装仓库中的包。"))
                )
            } else if brew.catalog.isEmpty {
                if brew.isLoadingCatalog || !brew.hasAttemptedCatalogLoad {
                    loadingView
                } else {
                    emptyCatalogView
                }
            } else if brew.filteredCatalog.isEmpty {
                emptyState
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Homebrew 探索")
        .task {
            // 目录与下载量互不依赖，并行读取可以少等一半时间。
            async let catalog: Void = brew.loadCatalog()
            async let popularity: Void = brew.loadPopularity()
            _ = await (catalog, popularity)
        }
        .sheet(isPresented: $showsTerminal) {
            BrewConsoleView()
                .environmentObject(brew)
        }
        .confirmationDialog(
            L.t("安装 %@？", confirmInstall?.name ?? ""),
            isPresented: Binding(
                get: { confirmInstall != nil },
                set: { if !$0 { confirmInstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = confirmInstall {
                Button(L.t("安装")) {
                    confirmInstall = nil
                    Task { await brew.install(entry) }
                }
            }
            Button(L.t("取消"), role: .cancel) { confirmInstall = nil }
        } message: {
            Text(L.t("会执行 %@。已安装的包不受影响。", confirmInstall?.installCommand ?? ""))
        }
        .confirmationDialog(
            L.t("安装「%@」？", confirmNameInstall ?? ""),
            isPresented: Binding(
                get: { confirmNameInstall != nil },
                set: { if !$0 { confirmNameInstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let name = confirmNameInstall {
                Button(L.t("安装")) {
                    confirmNameInstall = nil
                    Task { await brew.install([name], kind: installKind) }
                }
            }
            Button(L.t("取消"), role: .cancel) { confirmNameInstall = nil }
        } message: {
            Text(L.t("会执行 %@。已安装的包不受影响。", nameInstallCommand))
        }
    }

    /// 没有选中目录条目时，按搜索关键词直接安装。
    ///
    /// 目录可能因为版本更新、第三方 tap 或网络失败而缺少某个包，
    /// 这时仍然可以输入包名交给 `brew install` 处理。
    private var installKind: BrewPackageKind {
        brew.exploreKindFilter ?? .formula
    }

    private var nameInstallCommand: String {
        guard let name = confirmNameInstall else { return "" }
        return BrewPackage.command("install", kind: installKind, names: [name])
    }

    /// 可以按名称直接安装的搜索词：不含空格，且当前没有匹配结果。
    private var installableQuery: String? {
        guard brew.catalog.isEmpty == false, brew.filteredCatalog.isEmpty else { return nil }
        let query = brew.exploreSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !query.contains(where: { $0.isWhitespace }) else { return nil }
        return query
    }

    // MARK: - 顶部筛选

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L.t("搜索全部包名、别名或描述"), text: $brew.exploreSearchText)
                    .textFieldStyle(.plain)
                    .layoutPriority(1)

                if !brew.exploreSearchText.isEmpty {
                    Button {
                        brew.exploreSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(Text(L.t("清除搜索")))
                }

                Divider().frame(height: 18)

                // 包类型：全部 / Formula / Cask
                Picker("类型", selection: $brew.exploreKindFilter) {
                    Text(L.t("全部")).tag(BrewPackageKind?.none)
                    ForEach(BrewPackageKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .labelsHidden()
                .frame(width: 96)

                // 下载量统计范围：近 30 / 90 / 365 天。
                Picker("范围", selection: $brew.exploreRange) {
                    ForEach(BrewAnalyticsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .labelsHidden()
                .frame(width: 108)
                .help(Text(L.t("统计范围。Homebrew 只提供近 30、90、365 天的匿名下载量。")))

                // 排序方式。
                Picker("排序", selection: $brew.exploreSort) {
                    ForEach(BrewCatalogSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .labelsHidden()
                .frame(width: 96)

                Toggle(L.t("已弃用"), isOn: $brew.exploreShowsDeprecated)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help(Text(L.t("是否显示已标记为弃用或停止维护、但仍可安装的包。")))
                    .fixedSize()

                Spacer(minLength: 0)

                if brew.hasActiveExploreFilter {
                    Button {
                        brew.resetExploreFilters()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(Text(L.t("清除筛选")))
                }

                Button {
                    Task { await brew.reloadCatalog() }
                } label: {
                    Label(L.t("刷新目录"), systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(catalogRefreshHelp)
                .disabled(brew.isLoadingCatalog || brew.isRunningCommand)

                Button {
                    showsTerminal = true
                } label: {
                    Label(L.t("命令日志"), systemImage: "terminal")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(Text(L.t("在独立窗口中查看命令日志")))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider().opacity(0.6)

            HStack(spacing: 10) {
                // 显示条数放在这里，避免第一行控件过多被裁切。
                Picker("数量", selection: $brew.exploreLimit) {
                    ForEach(BrewCatalogLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 104)
                .help(Text(L.t("最多显示多少个包。输入搜索关键词时显示全部匹配项。")))

                Text(L.t("显示 %d / %d", brew.filteredCatalog.count, brew.catalog.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()

                if brew.popularity == nil && brew.hasAttemptedPopularityLoad && !brew.isLoadingPopularity {
                    Label(L.t("下载量统计不可用"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize()
                    Button(L.t("重试")) {
                        Task { await brew.loadPopularity(force: true) }
                    }
                    .controlSize(.small)
                }

                Spacer(minLength: 0)

                // 统计区间放在右侧，补充说明下载量对应的时间范围。
                if let range = brew.activeRanking?.dateRangeText {
                    Text(range)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }

                if brew.isLoadingCatalog || brew.isLoadingPopularity {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .background(.bar)
    }

    // MARK: - 状态视图

    /// 刷新按钮的提示：附带目录更新时间，省掉一行状态文字。
    private var catalogRefreshHelp: String {
        guard let updatedAt = brew.lastCatalogLoadedAt else {
            return L.t("重新下载 Homebrew 目录与下载量统计。")
        }
        return L.t("目录更新于 %@。重新下载目录与下载量。", updatedAt.formatted(date: .abbreviated, time: .shortened))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L.t("正在下载 Homebrew 目录，第一次约需下载 10 MB，可能需要十几秒…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCatalogView: some View {
        ContentUnavailableView {
            Label(L.t("目录为空"), systemImage: "safari")
        } description: {
            Text(L.t("还没有下载到 Homebrew 目录。请检查网络后重试。"))
        } actions: {
            Button(L.t("重新下载")) {
                Task { await brew.reloadCatalog() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L.t("没有符合条件的包"), systemImage: "safari")
        } description: {
            Text(L.t("请调整搜索内容或筛选条件。"))
        } actions: {
            if let query = installableQuery {
                Button(L.t("安装「%@」", query)) {
                    confirmNameInstall = query
                }
                .buttonStyle(.borderedProminent)
                .help(Text(L.t("没有在目录中找到匹配项时，可以直接按这个名称执行 brew install。")))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 表格

    private var table: some View {
        BrewCatalogTable(
            entries: brew.filteredCatalog,
            selection: $brew.selectedCatalogEntryID,
            rankingProvider: { brew.ranking(for: $0) },
            isInstalledProvider: { brew.isInstalled($0) },
            canInstall: !brew.isRunningCommand,
            onInstall: { confirmInstall = $0 }
        )
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            guard let id = ids.first, let entry = brew.catalogEntry(id: id) else { return }
            // 双击即安装；已安装的包则跳回「包」分区查看。
            if brew.isInstalled(entry) {
                brew.revealInstalled(entry)
            } else {
                confirmInstall = entry
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        let selected = ids.compactMap { brew.catalogEntry(id: $0) }

        if let entry = selected.first {
            Button(L.t("复制安装命令")) {
                brew.copyInstallCommand(entry)
            }
            Button(L.t("复制包名")) {
                BrewExport.copy(entry.name)
            }

            Divider()

            if brew.isInstalled(entry) {
                Button(L.t("查看已安装详情")) {
                    brew.revealInstalled(entry)
                }
            } else {
                Button(L.t("安装")) {
                    confirmInstall = entry
                }
            }

            if let url = entry.homepage.flatMap(URL.init(string:)) {
                Button(L.t("打开主页")) {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button(L.t("查看包详情")) {
                Task { await brew.run(L.t("查看 %@ 详情", entry.name), arguments: ["info", entry.commandName]) }
            }
        } else {
            Text(L.t("未选择包"))
        }
    }
}

// MARK: - 表格

private struct BrewCatalogTable: View {
    let entries: [BrewCatalogEntry]
    @Binding var selection: String?
    let rankingProvider: (BrewPackageKind) -> BrewPopularityRanking?
    let isInstalledProvider: (BrewCatalogEntry) -> Bool
    let canInstall: Bool
    let onInstall: (BrewCatalogEntry) -> Void

    var body: some View {
        Table(entries, selection: $selection) {
            TableColumn("排名") { entry in
                let rank = rankingProvider(entry.kind)?.rank(for: entry)
                Text(rank.map { "#\($0)" } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 48, ideal: 58, max: 70)

            TableColumn("包") { entry in
                HStack(spacing: 9) {
                    Image(systemName: entry.kind.symbol)
                        .foregroundStyle(entry.kind.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(entry.title)
                                .lineLimit(1)
                            if entry.isDeprecated {
                                BrewCatalogBadge(text: L.t("已弃用"), color: .orange)
                            }
                            if entry.isDisabled {
                                BrewCatalogBadge(text: L.t("已停用"), color: .red)
                            }
                            if isInstalledProvider(entry) {
                                BrewCatalogBadge(text: L.t("已安装"), color: .green)
                            }
                        }
                        Text(entry.summary ?? entry.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .width(min: 240, ideal: 340, max: 520)

            TableColumn("类型") { entry in
                Text(entry.kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.kind.color)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(entry.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .width(min: 70, ideal: 82, max: 110)

            TableColumn("下载量") { entry in
                let ranking = rankingProvider(entry.kind)
                Text(ranking?.countText(for: entry) ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(ranking?.count(for: entry) ?? 0 > 0 ? .primary : .tertiary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110, max: 150)

            TableColumn("占比") { entry in
                let ranking = rankingProvider(entry.kind)
                Text(ranking?.percentText(for: entry) ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 70, max: 90)

            TableColumn("版本") { entry in
                Text(entry.latestVersion ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 90, max: 140)

            TableColumn("Tap") { entry in
                Text(entry.tapText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 130, max: 180)

            TableColumn("操作") { entry in
                if isInstalledProvider(entry) {
                    Label(L.t("已安装"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Button(L.t("安装")) {
                        onInstall(entry)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(!canInstall)
                    .help(Text(L.t("安装 %@", entry.name)))
                }
            }
            .width(min: 58, ideal: 68, max: 88)
        }
    }
}

struct BrewCatalogBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}
