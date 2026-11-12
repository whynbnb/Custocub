import AppKit
import SwiftUI

@main
struct CustocubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = CustocubStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1200, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 860)
        .commands {
            CustocubCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

struct CustocubCommands: Commands {
    @ObservedObject var store: CustocubStore

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

        CommandGroup(replacing: .appSettings) {
            SettingsLink {
                Label("设置…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
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
