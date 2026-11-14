import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CustocubStore
    @EnvironmentObject private var brew: BrewStore

    @AppStorage("autoScanOnLaunch") private var autoScanOnLaunch = true
    @AppStorage("refreshOnActivate") private var refreshOnActivate = true
    @AppStorage("computeSizes") private var computeSizes = true
    @AppStorage("showDeveloperApps") private var showDeveloperApps = true
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearance.system.rawValue

    @State private var showingRestartAlert = false

    var body: some View {
        Form {
            Section("通用") {
                Picker("语言", selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .onChange(of: appLanguage) { _, newValue in
                    guard let language = AppLanguage(rawValue: newValue) else { return }
                    AppLanguage.set(language)
                    showingRestartAlert = true
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

                Text("切换语言后需要重新启动 Custocub。")
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

            Section("扫描") {
                Toggle("启动时自动扫描", isOn: $autoScanOnLaunch)
                Toggle("回到应用时自动刷新", isOn: $refreshOnActivate)
                Toggle("扫描后计算应用体积", isOn: $computeSizes)

                Text("关闭体积计算后，列表会更快出现；保存快照时仍会补齐体积。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("扫描目录") {
                Text("/Applications")
                Text("~/Applications")
                Text("/System/Applications")
                Text("/System/Library/CoreServices")
                Text("/Library/Apple/System/Applications")
            }
            .font(.caption.monospaced())

            Section("Homebrew") {
                LabeledContent("可执行文件") {
                    Text(brew.executablePath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                LabeledContent("已安装", value: brew.hasLoaded
                    ? L.t("%d 个包（Formula %d · Cask %d）", brew.packageCount, brew.formulaCount, brew.caskCount)
                    : L.t("尚未读取"))

                LabeledContent("快照", value: L.t("%d 个", brew.snapshots.count))

                HStack {
                    Button("重新读取 Homebrew 包列表") {
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

                Text("应用快照会额外记录当时安装的 Homebrew Cask；Homebrew 快照则记录 Formula 与 Cask，两者互相独立。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据") {
                HStack {
                    Button("重新扫描") {
                        Task { await store.refresh(ignoreRecentScan: true) }
                    }
                    .disabled(store.isScanning)

                    Button("清除图标缓存") {
                        IconProvider.shared.clear()
                    }

                    Button("清除体积缓存并重算") {
                        Task { await store.clearSizeCacheAndRefresh() }
                    }
                    .disabled(store.isScanning)

                    Spacer()
                }

                HStack {
                    Button("在访达中显示快照文件夹") {
                        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        let directory = support
                            .appendingPathComponent("Custocub", isDirectory: true)
                            .appendingPathComponent("Snapshots", isDirectory: true)
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }

                    Spacer()

                    Text(L.t("%d 个已保存快照", store.snapshots.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("关于") {
                LabeledContent("Custocub", value: "1.0")
                Text("Custocub = custos（守护） + cubby（收纳格）。用于清点 macOS 软件来源、架构与变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 700)
        .navigationTitle("Custocub 设置")
        .alert("语言已更改", isPresented: $showingRestartAlert) {
            Button("立即重启") {
                AppRestart.relaunch()
            }
            Button("稍后", role: .cancel) {}
        } message: {
            Text("重新启动 Custocub 后生效。")
        }
    }
}
