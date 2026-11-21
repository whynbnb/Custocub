import AppKit
import SwiftUI

@main
struct CustocubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CustocubStore()
    @StateObject private var brew = BrewStore()
    @StateObject private var localization = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(brew)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .id(localization.revision)
                .frame(minWidth: WorkspaceLayoutStore.windowMinWidth, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CustocubCommands(store: store, brew: brew, localization: localization)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(brew)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .id(localization.revision)
        }
    }
}

struct CustocubCommands: Commands {
    @ObservedObject var store: CustocubStore
    @ObservedObject var brew: BrewStore
    @ObservedObject var localization: LocalizationManager

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("扫描应用") {
                Task { await store.refresh(ignoreRecentScan: true) }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.isScanning)

            Button("保存快照") {
                Task { await store.saveSnapshot() }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(store.isScanning || store.isSavingSnapshot || !store.hasScanned || store.apps.isEmpty)

            Button("打开 Homebrew") {
                store.sidebarSelection = .brew
                Task { await brew.load() }
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!brew.isAvailable)

            Button("保存 Homebrew 快照") {
                Task { await brew.saveSnapshot() }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!brew.isAvailable || brew.isSavingSnapshot || brew.isRunningCommand || !brew.hasLoaded)
        }

        CommandGroup(replacing: .appInfo) {
            Button("关于 Custocub") {
                AboutPanel.show()
            }
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("导入快照…") {
                FileActions.importSnapshots(into: store)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("导出当前快照…") {
                FileActions.exportSelected(from: store)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(store.selectedSnapshot == nil)
        }

        CommandMenu("Homebrew") {
            Button("打开 Homebrew 升级") {
                store.sidebarSelection = .brew
                brew.section = .upgrade
                Task { await brew.load() }
            }
            .disabled(!brew.isAvailable)

            Divider()

            // 直接在这里切换升级策略，不用打开设置。
            Picker("升级策略", selection: $brew.upgradePolicy) {
                ForEach(BrewUpgradePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// 自定义「关于」面板：展示版本、开源仓库和许可证链接。
@MainActor
enum AboutPanel {
    private static let repositoryURL = URL(string: "https://github.com/whynbnb/Custocub")!
    private static let licenseURL = URL(string: "https://github.com/whynbnb/Custocub/blob/main/LICENSE")!

    static func show() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.2"

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Custocub",
            .applicationVersion: version,
            .credits: credits()
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3

        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]

        let result = NSMutableAttributedString()

        func appendLink(title: String, url: URL, showsURL: Bool) {
            var linkAttributes = base
            linkAttributes[.link] = url
            linkAttributes[.foregroundColor] = NSColor.linkColor

            if showsURL {
                result.append(NSAttributedString(string: title + "\n", attributes: base))
                result.append(NSAttributedString(string: url.absoluteString, attributes: linkAttributes))
            } else {
                result.append(NSAttributedString(string: title, attributes: linkAttributes))
            }
            result.append(NSAttributedString(string: "\n\n", attributes: base))
        }

        appendLink(title: L.t("开源地址"), url: repositoryURL, showsURL: true)
        appendLink(title: "MIT License", url: licenseURL, showsURL: false)
        result.append(NSAttributedString(string: "© 2026 0x574859", attributes: base))

        return result
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        AppLanguage.applyStoredPreference()
        AppAppearance.applyStoredPreference()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)





        DispatchQueue.main.async {
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
