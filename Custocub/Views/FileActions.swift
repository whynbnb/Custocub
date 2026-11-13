import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileActions {
    @MainActor
    static func importSnapshots(into store: CustocubStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L.t("选择 Custocub 导出的快照 JSON 文件")
        panel.prompt = L.t("导入")

        if panel.runModal() == .OK, let url = panel.url {
            store.importSnapshots(from: url)
        }
    }

    @MainActor
    static func exportSelected(from store: CustocubStore) {
        guard let snapshot = store.selectedSnapshot else { return }
        export(snapshot: snapshot, store: store)
    }

    @MainActor
    static func export(snapshot: AppSnapshot, store: CustocubStore) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = safeFileName("Custocub-\(snapshot.name)") + ".json"
        panel.message = L.t("导出快照，用于备份或在另一台 Mac 上导入")
        panel.prompt = L.t("导出")

        if panel.runModal() == .OK, let url = panel.url {
            store.exportSnapshot(snapshot, to: url)
        }
    }

    private static func safeFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}
