import Foundation

struct AppSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    var hostName: String
    var osVersion: String
    var apps: [AppRecord]
    /// 保存快照时本机的 Homebrew Cask 列表。旧快照没有该字段，解码为空数组。
    var casks: [BrewCaskRecord]
    var brewVersion: String?

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        hostName: String = Host.current().localizedName ?? "Mac",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        apps: [AppRecord],
        casks: [BrewCaskRecord] = [],
        brewVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.hostName = hostName
        self.osVersion = osVersion
        self.apps = apps
        self.casks = casks
        self.brewVersion = brewVersion
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case note
        case createdAt
        case hostName
        case osVersion
        case apps
        case casks
        case brewVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        hostName = try container.decodeIfPresent(String.self, forKey: .hostName) ?? "Mac"
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion) ?? ""
        apps = try container.decode([AppRecord].self, forKey: .apps)
        casks = try container.decodeIfPresent([BrewCaskRecord].self, forKey: .casks) ?? []
        brewVersion = try container.decodeIfPresent(String.self, forKey: .brewVersion)
    }

    var caskCount: Int { casks.count }

    /// 可导入回去重新安装的 cask token 列表。
    var caskTokens: [String] { casks.map(\.token) }

    var caskInstallCommand: String {
        BrewPackage.command("install", kind: .cask, names: caskTokens)
    }

    var brewfileText: String {
        BrewfileBuilder.text(
            formulae: [],
            casks: caskTokens,
            header: L.t("Custocub 应用快照 · %@ 的 Homebrew Cask", name)
        )
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
