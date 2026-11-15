import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("refreshOnActivate") private var refreshOnActivate = true

    @State private var showingComparison = false
    @State private var showingDeleteConfirmation = false
    @State private var showingBrewConsole = false

    var body: some View {
        // 两列结构：侧边栏 + 右侧工作区。
        //
        // 右侧工作区内部再用 HSplitView 分成「列表」和「详情」。
        // 之前用三列 NavigationSplitView，中间列和详情列会各自拥有
        // 独立的标题栏段，标题栏被一条竖线切成两块，看起来像三列。
        // 合并成一列后，标题、统计和工具栏是同一个 header。
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            if showsDetailPane {
                HSplitView {
                    content
                        .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)

                    detailColumn
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 430, maxHeight: .infinity)
                }
            } else {
                // 快照、服务、清理和诊断分区自己就是整页内容，
                // 不需要额外的详情列，直接铺满右侧工作区。
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, refreshOnActivate else { return }
            Task { await store.refreshIfStale() }
        }
        .onChange(of: store.sidebarSelection) { _, selection in
            guard selection == .own else { return }
            // 进入「开发者的应用」时清除会限制结果的筛选条件。
            store.searchText = ""
            store.sourceFilter = nil
            store.platformFilter = nil
            store.typeFilter = .all
            store.galleryStatusFilter = nil
        }
        .sheet(isPresented: $showingComparison) {
            ComparisonView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingBrewConsole) {
            BrewConsoleView()
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

    @ToolbarContentBuilder
    private var appToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showingComparison = true
            } label: {
                Label("比较快照", systemImage: "arrow.left.arrow.right")
            }
            .help("将当前状态或两个历史快照进行比较")
            .disabled(store.comparisonSnapshots.count < 2)

            Button {
                Task { await store.refresh(ignoreRecentScan: true) }
            } label: {
                Label("扫描应用", systemImage: "arrow.clockwise")
            }
            .help("重新扫描这台 Mac 上的应用")
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

                Button("删除当前快照…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(store.selectedSnapshot == nil)
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
            }
            .help("导入、导出和删除快照")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.activeSelection {
        case .installed, .own, .source:
            InstalledAppsView()
        case .brew:
            HomebrewView()
        case .gallery:
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
        guard store.activeSelection == .brew else { return true }

        switch brew.section {
        case .packages, .explore, .upgrade:
            return true
        case .snapshots, .services, .cleanup, .health:
            return false
        }
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
