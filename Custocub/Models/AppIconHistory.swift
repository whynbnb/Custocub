import Foundation

/// 某个应用在历史快照中的一次图标记录。
///
/// 只保留图标发生变化的快照：如果连续几个快照里的图标相同，
/// 只有第一次出现的那一个会出现在历史里。
struct AppIconHistoryEntry: Identifiable, Hashable, Sendable {
    let snapshotID: UUID
    let snapshotName: String
    let capturedAt: Date
    let version: String?
    let build: String?
    let iconData: Data

    var id: UUID { snapshotID }
}
