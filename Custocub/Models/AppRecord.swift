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
    var lastSeenAt: Date

    var id: String { path }

    var displayVersion: String {
        guard let version, !version.isEmpty else { return "未知" }
        return version
    }

    var displayBundleIdentifier: String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return "无 Bundle ID" }
        return bundleIdentifier
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
        if architectures.isEmpty { return "未知" }
        return architectures.joined(separator: " + ")
    }

    var displaySize: String {
        guard let sizeInBytes else { return "计算中…" }
        return ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    var typeTitle: String {
        isSystemApp ? "系统" : "第三方"
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
        installedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
    }

    var updatedAtText: String {
        updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知"
    }

    var lastSeenAtText: String {
        lastSeenAt.formatted(date: .abbreviated, time: .shortened)
    }

    // 供 Table 排序使用的非可选键。
    var versionSortValue: String { displayVersion }
    var sizeSortValue: Int64 { sizeInBytes ?? -1 }
    var updatedSortValue: Date { updatedAt ?? .distantPast }

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
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}
