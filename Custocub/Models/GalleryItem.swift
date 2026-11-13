import Foundation

/// 展示框中的条目。已安装应用来自实时扫描，已卸载应用来自历史快照。
struct GalleryItem: Identifiable, Hashable, Sendable {
    enum Status: String, CaseIterable, Identifiable, Sendable {
        case installed
        case uninstalled

        var id: Self { self }

        var title: String {
            switch self {
            case .installed: L.t("已安装")
            case .uninstalled: L.t("已卸载")
            }
        }

        var symbol: String {
            switch self {
            case .installed: "checkmark.circle.fill"
            case .uninstalled: "archivebox.fill"
            }
        }
    }

    let id: String
    let app: AppRecord
    let status: Status
    let lastSeenAt: Date?
    let snapshotName: String?

    var isInstalled: Bool { status == .installed }
}
