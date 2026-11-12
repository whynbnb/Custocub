import Foundation

struct AppSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    var hostName: String
    var osVersion: String
    var apps: [AppRecord]

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        hostName: String = Host.current().localizedName ?? "Mac",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        apps: [AppRecord]
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.hostName = hostName
        self.osVersion = osVersion
        self.apps = apps
    }

    var appCount: Int { apps.count }

    var totalSize: Int64 {
        apps.compactMap(\.sizeInBytes).reduce(0, +)
    }

    var totalSizeText: String {
        totalSize.formatted(.byteCount(style: .file))
    }

    var sourceCounts: [AppSource: Int] {
        Dictionary(grouping: apps, by: \.source).mapValues(\.count)
    }

    var systemCount: Int {
        apps.count { $0.isSystemApp }
    }

    var thirdPartyCount: Int {
        apps.count { !$0.isSystemApp }
    }

    var appStoreCount: Int {
        apps.count { $0.source.isAppStore }
    }

    var homebrewCount: Int {
        apps.count { $0.source == .homebrew }
    }
}
