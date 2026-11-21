import Foundation

/// 从历史快照汇总出的应用档案。
struct AppStory: Sendable {
    struct VersionEntry: Identifiable, Hashable, Sendable {
        let snapshotID: UUID
        let snapshotName: String
        let capturedAt: Date
        let version: String?
        let build: String?
        let source: AppSource
        let sizeInBytes: Int64?

        var id: String {
            "\(snapshotID.uuidString)|\(version ?? "")|\(build ?? "")"
        }
    }

    struct SourceEntry: Identifiable, Hashable, Sendable {
        let snapshotID: UUID
        let snapshotName: String
        let capturedAt: Date
        let source: AppSource

        var id: UUID { snapshotID }
    }

    let app: AppRecord
    let firstSeen: AppSnapshot?
    let lastSeen: AppSnapshot?
    let appearances: Int
    let totalSnapshots: Int
    let versions: [VersionEntry]
    let sourceChanges: [SourceEntry]
    let iconHistory: [AppIconHistoryEntry]
    let isCurrentlyInstalled: Bool
}
