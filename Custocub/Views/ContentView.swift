import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("refreshOnActivate") private var refreshOnActivate = true
    /// 应用详情面板默认收起，展开后可由工具栏按钮再次关闭。
    @AppStorage("showsAppDetailPane") private var showsAppDetailPane = false

    @State private var detailPaneWidth = DetailPaneWidth.load()
    @State private var detailDragStartWidth: CGFloat?

    /// 按住 ⌥ 时刷新按钮切换成「全量刷新」样式，给用户明确反馈。
    @State private var optionHeld = false

    @State private var showingComparison = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBrewConsole = false
    @State private var showingCommandPalette = false

    var body: some View {
        // 两列结构：侧边栏 + 右侧工作区。
        //
        // 右侧工作区内部再用 HSplitView 分成「列表」和「详情」。
        // 之前用三列 NavigationSplitView，中间列和详情列会各自拥有
        // 独立的标题栏段，标题栏被一条竖线切成两块，看起来像三列。
        // 合并成一列后，标题、统计和工具栏是同一个 header。
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: WorkspaceLayoutStore.sidebarMinWidth,
                    ideal: WorkspaceLayoutStore.sidebarWidth(for: workspaceMode),
                    max: WorkspaceLayoutStore.sidebarMaxWidth
                )
                .background(SidebarWidthMemory(mode: workspaceMode))
        } detail: {
            detailArea
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowWidthMemory(mode: workspaceMode))
        .toolbar {
            if store.activeSelection != .brew {
                appToolbar
            }
        }
        .task {
            guard autoScanOnLaunch, !store.hasScanned else { return }
            await store.refresh(ignoreRecentScan: true)
        }
        .task {
            // 侧边栏需要 Homebrew 包数量，启动后后台读取一次。
            // 功能关闭或未安装时直接跳过，不派生任何 brew 进程。
            guard brew.isAvailable else { return }
            await brew.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .custocubShowBrewConsole)) { _ in
            showingBrewConsole = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .custocubShowCommandPalette)) { _ in
            showingCommandPalette = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                optionHeld = false
            }
            guard phase == .active, refreshOnActivate else { return }
            Task { await store.refreshIfStale() }
        }
        .onModifierKeysChanged(mask: .option) { _, modifiers in
            optionHeld = modifiers.contains(.option)
        }
        .onChange(of: store.sidebarSelection) { _, selection in
            guard selection == .own else { return }
            // 进入「开发者的应用」时清除会限制结果的筛选条件。
            store.searchText = ""
            store.sourceFilter = nil
            store.platformFilter = nil
            store.typeFilter = .all
            store.gallerySourceFilters = []
            store.galleryPlatformFilters = []
            store.galleryTypeFilters = []
            store.galleryStatusFilters = []
        }
        .sheet(isPresented: $showingComparison) {
            ComparisonView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingBrewConsole) {
            BrewConsoleView()
                .environmentObject(brew)
        }
        .sheet(isPresented: $showingCommandPalette) {
            CommandPaletteView()
                .environmentObject(store)
                .environmentObject(brew)
        }
        .confirmationDialog(
            "删除这个快照？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let snapshot = store.selectedSnapshot {
                Button(L.t("删除「%@」", snapshot.name), role: .destructive) {
                    store.deleteSnapshot(id: snapshot.id)
                }
            }
        } message: {
            Text("此操作无法撤销。导出的 JSON 文件不会受到影响。")
        }
        .alert("发生错误", isPresented: errorPresented) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? L.t("未知错误"))
        }
        .alert("Homebrew 出错", isPresented: brewErrorPresented) {
            Button("好") { brew.errorMessage = nil }
        } message: {
            Text(brew.errorMessage ?? L.t("未知错误"))
        }
    }

    /// 应用列表与详情之间的分隔条，可拖动调整详情宽度。
    private var detailPaneDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if detailDragStartWidth == nil {
                            detailDragStartWidth = detailPaneWidth
                        }
                        guard let start = detailDragStartWidth else { return }
                        detailPaneWidth = DetailPaneWidth.clamp(
                            start - value.translation.width
                        )
                    }
                    .onEnded { _ in
                        detailDragStartWidth = nil
                        DetailPaneWidth.save(detailPaneWidth)
                    }
            )
    }

    @ToolbarContentBuilder
    private var appToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsAppDetailPane.toggle()
                }
            } label: {
                Label(
                    L.t(showsAppDetailPane ? "隐藏详情面板" : "显示详情面板"),
                    systemImage: "rectangle.righthalf.inset.filled"
                )
            }
            .help(Text(L.t(showsAppDetailPane ? "隐藏详情面板" : "显示详情面板")))

            Button {
                showingComparison = true
            } label: {
                Label("比较快照", systemImage: "arrow.left.arrow.right")
            }
            .help("将当前状态或两个历史快照进行比较")
            .disabled(store.comparisonSnapshots.count < 2)

            Button {
                // 按住 ⌥ 点击时做全量刷新：图标和体积都重新生成。
                let fullRefresh = optionHeld || NSEvent.modifierFlags.contains(.option)
                Task { await store.refresh(ignoreRecentScan: true, fullRefresh: fullRefresh) }
            } label: {
                Label(
                    L.t(optionHeld ? "全量刷新" : "扫描应用"),
                    systemImage: optionHeld ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise"
                )
                .foregroundStyle(optionHeld ? Color.orange : Color.primary)
            }
            .help(Text(L.t(optionHeld
                ? "全量刷新所有应用图标和体积"
                : "重新扫描这台 Mac 上的应用（按住 ⌥ 全量刷新图标和体积）")))
            .disabled(store.isScanning || store.isSavingSnapshot)

            Button {
                Task { await store.saveSnapshot() }
            } label: {
                Label("保存快照", systemImage: "camera.fill")
            }
            .help("把当前应用清单保存为历史快照")
            .disabled(store.isScanning || store.isSavingSnapshot || !store.hasScanned || store.apps.isEmpty)

            Menu {
                Button("导入快照…") {
                    FileActions.importSnapshots(into: store)
                }
                Button("导出当前快照…") {
                    FileActions.exportSelected(from: store)
                }
                .disabled(store.selectedSnapshot == nil)

                Divider()

                Menu("导出报告") {
                    ForEach(InventoryReportFormat.allCases) { format in
                        Button(format.menuTitle) {
                            exportReport(format)
                        }
                    }
                }
                .disabled(reportSource == nil)

                Divider()

                Button("删除当前快照…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(store.selectedSnapshot == nil)
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .help(Text(L.t("导入、导出快照与报告")))
        }
    }

    /// 右侧工作区：列表单独铺满，或按需和详情并排。
    @ViewBuilder
    private var detailArea: some View {
        if showsDetailPane {
            if store.activeSelection == .brew {
                brewDetailSplit
            } else if showsAppDetailPane {
                appDetailSplit
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // 快照、服务、清理和诊断分区自己就是整页内容，
            // 不需要额外的详情列，直接铺满右侧工作区。
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Homebrew 的列表与详情使用系统分栏。
    private var brewDetailSplit: some View {
        HSplitView {
            content
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

            detailColumn
                .frame(minWidth: 300, idealWidth: 350, maxWidth: 430, maxHeight: .infinity)
        }
    }

    /// 应用列表与详情：默认收起详情，展开后宽度可拖动并记住。
    private var appDetailSplit: some View {
        HStack(spacing: 0) {
            content
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            detailPaneDivider

            detailColumn
                .frame(width: detailPaneWidth)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.activeSelection {
        case .installed, .own, .source:
            InstalledAppsView()
        case .newlyInstalled:
            NewlyInstalledAppsView()
        case .updated:
            UpdatedAppsView()
        case .uninstalled:
            UninstalledAppsView()
        case .insights:
            InsightsView()
        case .brew:
            HomebrewView()
        case .gallery, .favorites, .collection:
            GalleryView()
        case .snapshot(let id):
            if let snapshot = store.snapshots.first(where: { $0.id == id }) {
                SnapshotAppsView(snapshot: snapshot)
            } else {
                ContentUnavailableView(
                    "找不到这个快照",
                    systemImage: "camera.badge.ellipsis",
                    description: Text("它可能已经被删除。")
                )
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if store.activeSelection == .brew {
            if brew.section == .explore {
                BrewCatalogDetailView(
                    entry: brew.selectedCatalogEntry,
                    ranking: brew.selectedCatalogEntry.flatMap { brew.ranking(for: $0.kind) }
                )
            } else {
                BrewPackageDetailView(package: brew.selectedPackage)
            }
        } else {
            AppDetailView(context: store.selectedAppContext)
        }
    }

    /// 右侧是否需要「列表 + 详情」两栏。
    ///
    /// Homebrew 的快照、服务分区在视图内部已经有自己的左右分栏，
    /// 清理和诊断则是单页内容，多出来的详情列只会显示一个空状态。
    private var showsDetailPane: Bool {
        switch store.activeSelection {
        case .brew:
            switch brew.section {
            case .packages, .explore, .upgrade:
                return true
            case .snapshots, .services, .cleanup, .health:
                return false
            }
        case .newlyInstalled, .updated, .uninstalled:
            // 没有快照时整页显示提示，不保留空的详情列。
            return store.latestSnapshot != nil
        case .insights:
            return false
        default:
            return true
        }
    }

    /// 当前工作区：Homebrew 和应用各记一套窗口与侧边栏宽度。
    private var workspaceMode: WorkspaceLayoutStore.Mode {
        WorkspaceLayoutStore.Mode.mode(for: store.activeSelection)
    }

    /// 报告导出的数据源：优先当前选中的历史快照，否则用当前扫描结果。
    private var reportSource: InventoryReportSource? {
        if let snapshot = store.selectedSnapshot {
            return .snapshot(snapshot)
        }
        if !store.apps.isEmpty {
            return .currentScan(apps: store.apps, lastScanAt: store.lastScanAt)
        }
        if let latest = store.latestSnapshot {
            return .snapshot(latest)
        }
        return nil
    }

    private func exportReport(_ format: InventoryReportFormat) {
        guard let source = reportSource else { return }
        FileActions.exportReport(source: source, format: format, store: store)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var brewErrorPresented: Binding<Bool> {
        Binding(
            get: { brew.errorMessage != nil },
            set: { if !$0 { brew.errorMessage = nil } }
        )
    }
}
