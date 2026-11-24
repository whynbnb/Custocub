import Foundation

/// 一次扫描得到的应用记录。快照中保存的也是这个结构。
struct AppRecord: Identifiable, Codable, Hashable, Sendable {
    var path: String
    var resolvedPath: String
    var name: String
    var bundleIdentifier: String?
    var version: String?
    var build: String?
    var executablePath: String?
    var source: AppSource
    var isSystemApp: Bool
    var architectures: [String]
    var isIOSApp: Bool
    var wrappedAppPath: String?
    var sizeInBytes: Int64?
    var installedAt: Date?
    var updatedAt: Date?
    var minimumSystemVersion: String?
    var iconData: Data?
    /// 图标内容指纹。快照缓存用它判断图标是否变化，不必把整张 PNG 留在内存里。
    var iconFingerprint: String? = nil
    /// 快照缓存中的图标位置；只在派生缓存里使用，原始快照 JSON 不依赖它。
    var iconSnapshotID: UUID? = nil
    var lastSeenAt: Date
    var steamAppID: String? = nil
    var isOwnApp: Bool? = nil

    var id: String { path }

    var isOwn: Bool { isOwnApp == true }

    /// 来源管理器本身（Steam 客户端、JetBrains Toolbox 客户端）。
    /// 浏览对应来源时，它们会作为不计数的管理工具额外显示。
    var managerSource: AppSource? {
        switch bundleIdentifier?.lowercased() {
        case "com.valvesoftware.steam": .steam
        case "com.jetbrains.toolbox": .jetbrainsToolbox
        default: nil
        }
    }

    var displayVersion: String {
        guard let version, !version.isEmpty else { return L.t("未知") }
        return version
    }

    var displayBundleIdentifier: String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return L.t("无 Bundle ID") }
        return bundleIdentifier
    }

    /// 列表/详情标题下方的副标题：没有 Bundle ID 的 Steam 快捷方式显示 App ID。
    var listSubtitle: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        if let steamAppID {
            return "Steam App ID \(steamAppID)"
        }
        return L.t("无 Bundle ID")
    }

    var platform: AppPlatform {
        if isIOSApp { return .ios }

        let set = Set(architectures)
        let arm = set.contains("arm64") || set.contains("arm64_32") || set.contains("arm")
        let intel = set.contains("x86_64") || set.contains("i386")

        if arm && intel { return .universal }
        if arm { return .appleSilicon }
        if intel { return .intel }
        return .unknown
    }

    var architectureText: String {
        if architectures.isEmpty { return L.t("未知") }
        return architectures.joined(separator: " + ")
    }

    var displaySize: String {
        guard let sizeInBytes else { return L.t("计算中…") }
        return sizeInBytes.formatted(.byteCount(style: .file))
    }

    var typeTitle: String {
        isSystemApp ? L.t("系统") : L.t("第三方")
    }

    /// 用于跨快照识别同一应用。Bundle ID 更稳定，缺失时退回安装路径。
    var bundleKey: String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return path }
        return bundleIdentifier
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    var installedAtText: String {
        installedAt?.formatted(date: .abbreviated, time: .shortened) ?? L.t("未知")
    }

    var updatedAtText: String {
        updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? L.t("未知")
    }

    var lastSeenAtText: String {
        lastSeenAt.formatted(date: .abbreviated, time: .shortened)
    }

    private static let listDateStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)

    var updatedAtListText: String {
        updatedAt?.formatted(Self.listDateStyle) ?? L.t("未知")
    }

    // 供 Table 排序使用的非可选键。
    var versionSortValue: String { displayVersion }
    var sizeSortValue: Int64 { sizeInBytes ?? -1 }
    var updatedSortValue: Date { updatedAt ?? .distantPast }
    var sourceSortValue: String { source.title }
    var platformSortValue: String { platform.shortTitle }
    var typeSortValue: String { typeTitle }

    // 快照比较不应把「最后出现时间」和图标数据视为内容变化。
    static func == (lhs: AppRecord, rhs: AppRecord) -> Bool {
        lhs.path == rhs.path
            && lhs.resolvedPath == rhs.resolvedPath
            && lhs.name == rhs.name
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.version == rhs.version
            && lhs.build == rhs.build
            && lhs.executablePath == rhs.executablePath
            && lhs.source == rhs.source
            && lhs.isSystemApp == rhs.isSystemApp
            && lhs.architectures == rhs.architectures
            && lhs.isIOSApp == rhs.isIOSApp
            && lhs.wrappedAppPath == rhs.wrappedAppPath
            && lhs.sizeInBytes == rhs.sizeInBytes
            && lhs.installedAt == rhs.installedAt
            && lhs.updatedAt == rhs.updatedAt
            && lhs.minimumSystemVersion == rhs.minimumSystemVersion
            && lhs.steamAppID == rhs.steamAppID
            && lhs.isOwnApp == rhs.isOwnApp
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
