import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("常规", systemImage: "gearshape") }

            AppsSettingsTab()
                .tabItem { Label("应用", systemImage: "square.grid.2x2") }

            HomebrewSettingsTab()
                .tabItem { Label("Homebrew", systemImage: "mug") }

            DataSettingsTab()
                .tabItem { Label("数据", systemImage: "internaldrive") }

            AboutSettingsTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - 通用

private struct GeneralSettingsTab: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    var body: some View {
        Form {
            Section("语言与外观") {
                Picker("语言", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .onChange(of: appLanguage) { _, newValue in
                    guard let language = AppLanguage(rawValue: newValue) else { return }
                    AppLanguage.set(language)
                }

                Picker("外观", selection: $appearanceMode) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .onChange(of: appearanceMode) { _, newValue in
                    guard let appearance = AppAppearance(rawValue: newValue) else { return }
                    AppAppearance.set(appearance)
                }
            }

            Section {
                Text("语言与外观会立即生效，无需重新启动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 应用

private struct AppsSettingsTab: View {
    @EnvironmentObject private var store: CustocubStore

    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("refreshOnActivate") private var refreshOnActivate = true
    @AppStorage("computeSizes") private var computeSizes = true
    @AppStorage("showDeveloperApps") private var showDeveloperApps = true

    var body: some View {
        Form {
            Section("扫描") {
                Toggle("启动时自动扫描", isOn: $autoScanOnLaunch)
                Toggle("回到应用时自动刷新", isOn: $refreshOnActivate)
                Toggle("扫描后计算应用体积", isOn: $computeSizes)

                Text("关闭体积计算后，列表会更快出现；保存快照时仍会补齐体积。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("开发者的应用") {
                Toggle("显示开发者的应用", isOn: $showDeveloperApps)

                LabeledContent("Bundle ID 前缀", value: AppConstants.developerBundlePrefix)
                    .textSelection(.enabled)

                Text("Bundle ID 以 me.whynbnb. 开头的应用会归入「开发者的应用」。匹配数量大于 2 时才会在侧边栏显示该分类。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("扫描目录") {
                ForEach(AppConstants.scanDirectories, id: \.self) { directory in
                    Text(directory)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    Button("立即重新扫描") {
                        Task { await store.refresh(ignoreRecentScan: true) }
                    }
                    .disabled(store.isScanning)

                    if store.isScanning {
                        ProgressView().controlSize(.small)
                    }

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Homebrew

private struct HomebrewSettingsTab: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore

    var body: some View {
        Form {
            Section {
                Toggle("启用 Homebrew 功能", isOn: $brew.isEnabled)

                Text("关闭后不会执行任何 brew 命令，也不会读取包列表。应用清单中的 Homebrew 来源、已保存的 Homebrew 快照都会保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("状态") {
                LabeledContent("检测结果") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                    }
                }

                LabeledContent("可执行文件") {
                    Text(brew.executablePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                LabeledContent("版本", value: brew.detectedVersion?.description ?? L.t("尚未读取"))

                LabeledContent("安装前缀") {
                    Text(brew.prefix)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                LabeledContent("已安装", value: brew.hasLoaded
                    ? L.t("%d 个包（Formula %d · Cask %d）", brew.packageCount, brew.formulaCount, brew.caskCount)
                    : L.t("尚未读取"))

                LabeledContent("Homebrew 快照", value: L.t("%d 个", brew.snapshots.count))
            }

            Section {
                HStack {
                    Button("重新检测 Homebrew") {
                        brew.rediscover()
                    }

                    Button("重新读取包列表") {
                        Task { await brew.load(force: true) }
                    }
                    .disabled(!brew.isAvailable || brew.isLoading || brew.isRunningCommand)

                    Button("打开 Homebrew 界面") {
                        store.sidebarSelection = .brew
                        Task { await brew.load() }
                    }
                    .disabled(!brew.isAvailable)

                    Spacer()
                }
            } footer: {
                Text("应用快照会额外记录当时安装的 Homebrew Cask；Homebrew 快照则记录 Formula 与 Cask，两者互相独立。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if brew.isDisabledByUser { return L.t("已关闭") }
        if brew.isMissingInstallation { return L.t("未安装") }
        return L.t("已启用")
    }

    private var statusColor: Color {
        if brew.isDisabledByUser { return .secondary }
        if brew.isMissingInstallation { return .orange }
        return .green
    }
}

// MARK: - 数据

private struct DataSettingsTab: View {
    @EnvironmentObject private var store: CustocubStore

    var body: some View {
        Form {
            Section("缓存") {
                HStack {
                    Button("清除图标缓存") {
                        IconProvider.shared.clear()
                    }

                    Button("清除体积缓存并重算") {
                        Task { await store.clearSizeCacheAndRefresh() }
                    }
                    .disabled(store.isScanning)

                    Spacer()
                }

                Text("体积缓存位于 ~/Library/Application Support/Custocub/size-cache.json，7 天后过期。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Homebrew 探索目录") {
                HStack {
                    Button("清除目录缓存") {
                        BrewCatalogService.clearCache()
                    }

                    Spacer()
                }

                Text(L.t("探索目录缓存在 ~/Library/Application Support/Custocub/BrewCatalog，目录 1 天、下载量 1 小时后过期。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快照存储") {
                LabeledContent("应用快照", value: L.t("%d 个", store.snapshots.count))
                LabeledContent("存储位置") {
                    Text(L.t("~/Library/Application Support/Custocub/Snapshots"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                HStack {
                    Button("在访达中显示快照文件夹") {
                        openSnapshotsFolder()
                    }

                    Button("在访达中显示 Homebrew 快照") {
                        openBrewSnapshotsFolder()
                    }

                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openSnapshotsFolder() {
        open(directory: "Snapshots")
    }

    private func openBrewSnapshotsFolder() {
        open(directory: "BrewSnapshots")
    }

    private func open(directory name: String) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }
}

// MARK: - 关于

private struct AboutSettingsTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custocub")
                            .font(.title3.weight(.semibold))
                        Text(L.t("版本 %@（%@）", version, build))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Custocub = custos（守护） + cubby（收纳格）。用于清点 macOS 软件来源、架构与变化。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("链接") {
                Link(destination: URL(string: "https://github.com/whynbnb/Custocub")!) {
                    Label("开源地址", systemImage: "link")
                }

                Link(destination: URL(string: "https://github.com/whynbnb/Custocub/blob/main/LICENSE")!) {
                    Label("MIT License", systemImage: "doc.text")
                }
            }

            Section {
                Text("© 2026 0x574859")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
