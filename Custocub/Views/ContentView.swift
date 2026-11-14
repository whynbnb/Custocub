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
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } content: {
            content
                .navigationSplitViewColumnWidth(min: 650, ideal: 880)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 430)
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
            BrewPackageDetailView(package: brew.selectedPackage)
        } else {
            AppDetailView(context: store.selectedAppContext)
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
