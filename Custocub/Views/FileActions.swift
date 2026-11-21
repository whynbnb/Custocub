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

    @MainActor
    static func exportReport(
        source: InventoryReportSource,
        format: InventoryReportFormat,
        store: CustocubStore
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = safeFileName(
            "Custocub-\(source.title)-\(dateStamp())"
        ) + "." + format.fileExtension
        panel.message = L.t("导出当前应用清单为 HTML、PDF 或 CSV")
        panel.prompt = L.t("导出")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .html:
                try InventoryReport.html(source).write(to: url, atomically: true, encoding: .utf8)
            case .csv:
                try InventoryReport.csv(source).write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                try InventoryReport.pdf(source).write(to: url, options: .atomic)
            }
            store.statusMessage = L.t("已导出报告 · %@", url.lastPathComponent)
        } catch {
            store.errorMessage = L.t("无法导出报告：%@", error.localizedDescription)
        }
    }

    @MainActor
    static func exportShareCard(app: AppRecord, story: AppStory, store: CustocubStore) {
        let renderer = ImageRenderer(content: AppShareCard(app: app, story: story))
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            store.errorMessage = L.t("无法导出分享卡片：%@", L.t("无法生成图片"))
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = safeFileName(
            "Custocub-\(app.name)-\(dateStamp())"
        ) + ".png"
        panel.message = L.t("导出应用分享卡片")
        panel.prompt = L.t("导出")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try png.write(to: url, options: .atomic)
            store.statusMessage = L.t("已导出分享卡片 · %@", url.lastPathComponent)
        } catch {
            store.errorMessage = L.t("无法导出分享卡片：%@", error.localizedDescription)
        }
    }

    static func safeFileName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static func dateStamp() -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
