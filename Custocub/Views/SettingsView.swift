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

    @AppStorage(BrewProxySettings.Keys.enabled) private var proxyEnabled = false
    @AppStorage(BrewProxySettings.Keys.kind) private var proxyKindRaw = BrewProxyKind.socks5.rawValue
    @AppStorage(BrewProxySettings.Keys.host) private var proxyHost = ""
    @AppStorage(BrewProxySettings.Keys.port) private var proxyPort = BrewProxySettings.defaultPortText
    @AppStorage(BrewProxySettings.Keys.overrideGit) private var proxyOverridesGit = false

    @State private var proxyTest: ProxyTestState = .idle
    @State private var gitProxyEntries: [GitProxyEntry] = []
    @State private var isLoadingGitProxy = false

    /// 代理连通性测试的界面状态。
    private enum ProxyTestState: Equatable {
        case idle
        case testing
        case success(milliseconds: Int)
        case failure(String)
    }

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

            proxySection

            upgradePolicySection

            gitProxySection

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
        .onChange(of: proxySettings) { _, _ in
            proxyTest = .idle
        }
        .task {
            await loadGitProxy()
        }
    }

    // MARK: - 升级策略

    private var upgradePolicySection: some View {
        Section {
            Picker("升级策略", selection: $brew.upgradePolicy) {
                ForEach(BrewUpgradePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.segmented)

            Text(brew.upgradePolicy.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if brew.upgradePolicy == .standard {
                Text("Homebrew 7 默认会接管版本落后的自动更新 Cask。想要完全跳过它们，请选择非贪婪。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("升级")
        } footer: {
            Text("策略同时影响「可更新」数量、升级列表和实际执行的 brew 命令，不受 shell 里 HOMEBREW_* 环境变量的影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 代理

    private var proxySection: some View {
        Section {
            Toggle("为 Homebrew 启用代理", isOn: $proxyEnabled)

            Picker("协议", selection: proxyKindBinding) {
                ForEach(BrewProxyKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!proxyEnabled)

            LabeledContent("主机") {
                TextField("192.168.1.10", text: $proxyHost)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .disabled(!proxyEnabled)
            }

            LabeledContent("端口") {
                TextField("1080", text: $proxyPort)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .disabled(!proxyEnabled)
            }

            if proxyEnabled,
               !proxyHost.trimmingCharacters(in: .whitespaces).isEmpty,
               !proxySettings.isConfigured {
                Label("主机或端口格式不正确。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 10) {
                Button("测试连接") {
                    testProxy()
                }
                .disabled(!proxyEnabled || !proxySettings.isConfigured || proxyTest == .testing)

                proxyStatusView

                Spacer(minLength: 0)
            }

            Toggle("接管 Git 代理配置（仅 brew 子进程）", isOn: $proxyOverridesGit)
                .disabled(!proxyEnabled)

            Text("开启后，brew 执行 git fetch（例如 brew update）时也会使用上面的代理。只向子进程注入命令级配置，不会修改 Git 全局配置。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("代理会用于 brew 命令以及「探索」目录的下载，支持 SOCKS5 与 HTTP。SOCKS5 会通过代理解析域名。Git 的代理配置请在下方查看。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("网络代理")
        }
    }

    @ViewBuilder
    private var proxyStatusView: some View {
        switch proxyTest {
        case .idle:
            EmptyView()
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在测试…")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        case .success(let milliseconds):
            Label(L.t("连接成功（%d 毫秒）", milliseconds), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(L.t("连接失败：%@", message), systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var proxySettings: BrewProxySettings {
        BrewProxySettings(
            isEnabled: proxyEnabled,
            kind: BrewProxyKind(rawValue: proxyKindRaw) ?? .socks5,
            host: proxyHost,
            port: proxyPort,
            overridesGitProxy: proxyOverridesGit
        )
    }

    private var proxyKindBinding: Binding<BrewProxyKind> {
        Binding(
            get: { BrewProxyKind(rawValue: proxyKindRaw) ?? .socks5 },
            set: { proxyKindRaw = $0.rawValue }
        )
    }

    private func testProxy() {
        let settings = proxySettings
        proxyTest = .testing
        Task {
            let result = await settings.testConnection()
            switch result {
            case .success(let milliseconds):
                proxyTest = .success(milliseconds: milliseconds)
            case .failure(let message):
                proxyTest = .failure(message)
            }
        }
    }

    // MARK: - Git 代理

    private var gitProxySection: some View {
        Section {
            if isLoadingGitProxy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("读取中…")
                        .foregroundStyle(.secondary)
                }
            } else if gitProxyEntries.isEmpty {
                Text("未配置 Git 代理")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(gitProxyEntries) { entry in
                    LabeledContent(entry.key) {
                        Text(entry.value)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            }

            HStack {
                Button("重新读取") {
                    Task { await loadGitProxy() }
                }
                .disabled(isLoadingGitProxy)

                Spacer()
            }

            Text("只读显示 git config --global 中的代理设置，修改请使用 git config 命令。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("关闭覆盖开关时，Git 自身配置的代理会优先于应用里的代理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Git 全局代理配置")
        }
    }

    private func loadGitProxy() async {
        isLoadingGitProxy = true
        gitProxyEntries = await GitProxyService.loadGlobalProxyEntries()
        isLoadingGitProxy = false
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2"
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
