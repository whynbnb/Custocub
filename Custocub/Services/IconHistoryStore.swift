import AppKit
import CryptoKit
import Foundation

/// 一次图标变化记录。
struct IconHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    /// PNG 文件名，同时作为条目标识。
    let id: String
    let capturedAt: Date
    let version: String?
    let build: String?
    let hash: String
    /// 第一次记录时的图标，不计入「图标已更新」。
    let isBaseline: Bool

    var fileName: String { id }
}

private struct IconHistoryIndex: Codable, Sendable {
    var entries: [IconHistoryEntry] = []
}

/// 保存软件图标的历史版本。
///
/// 每个应用一个目录，里面是若干个 PNG 和一个索引文件。
/// 第一次检测到图标变化时，会把旧图标记为 baseline，再把新图标记为一次更新；
/// 之后每次变化追加一条记录，最多保留 `maxEntries` 个版本。
actor IconHistoryStore {
    static let shared = IconHistoryStore()

    private static let maxEntries = 24
    private let root: URL
    private let summaryURL: URL
    private var indexes: [String: IconHistoryIndex] = [:]
    private var summary: [String: Date]?
    private let fileManager = FileManager.default

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent("IconHistory", isDirectory: true)
        summaryURL = root.appendingPathComponent("Summary.json")
    }

    /// 应用在历史记录中的稳定标识：优先 Bundle ID，没有时用路径。
    nonisolated static func key(for app: AppRecord) -> String {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }
        return app.path
    }

    /// 每个应用最近一次「非 baseline」的图标变化时间。
    func latestChangeDates() -> [String: Date] {
        loadSummary()
        return summary ?? [:]
    }

    /// 某个应用的图标历史，按时间从旧到新排列。
    func entries(forKey key: String) -> [IconHistoryEntry] {
        loadIndex(key).entries.sorted { $0.capturedAt < $1.capturedAt }
    }

    func imageData(for entry: IconHistoryEntry, key: String) -> Data? {
        try? Data(contentsOf: directory(for: key).appendingPathComponent(entry.fileName))
    }

    /// 如果还没有任何历史，把旧图标记为起始版本。已有记录时什么都不做。
    func recordBaselineIfNeeded(app: AppRecord, iconData: Data) {
        let key = Self.key(for: app)
        var index = loadIndex(key)
        guard index.entries.isEmpty else { return }

        append(
            app: app,
            iconData: iconData,
            capturedAt: app.updatedAt ?? Date(),
            isBaseline: true,
            key: key,
            index: &index
        )
    }

    /// 记录当前图标。与最新记录相同则忽略；不同则追加为一次更新。
    func record(app: AppRecord, iconData: Data) {
        let key = Self.key(for: app)
        var index = loadIndex(key)
        let hash = Self.hash(iconData)

        if let last = index.entries.last, last.hash == hash {
            return
        }

        let isBaseline = index.entries.isEmpty
        append(
            app: app,
            iconData: iconData,
            capturedAt: isBaseline ? (app.updatedAt ?? Date()) : Date(),
            isBaseline: isBaseline,
            key: key,
            index: &index
        )
    }

    // MARK: - 存储

    private func append(
        app: AppRecord,
        iconData: Data,
        capturedAt: Date,
        isBaseline: Bool,
        key: String,
        index: inout IconHistoryIndex
    ) {
        let hash = Self.hash(iconData)
        let stamp = Int(capturedAt.timeIntervalSince1970)
        let fileName = "\(stamp)-\(hash.prefix(12)).png"
        let directory = directory(for: key)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try iconData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return
        }

        index.entries.append(
            IconHistoryEntry(
                id: fileName,
                capturedAt: capturedAt,
                version: app.version,
                build: app.build,
                hash: hash,
                isBaseline: isBaseline
            )
        )

        // 只保留最近的若干个版本，避免历史无限增长。
        while index.entries.count > Self.maxEntries {
            let removed = index.entries.removeFirst()
            try? fileManager.removeItem(at: directory.appendingPathComponent(removed.fileName))
        }

        indexes[key] = index
        saveIndex(key)

        if !isBaseline {
            loadSummary()
            summary?[key] = capturedAt
            saveSummary()
        }
    }

    private func directory(for key: String) -> URL {
        root.appendingPathComponent(Self.safeName(key), isDirectory: true)
    }

    private func indexURL(for key: String) -> URL {
        directory(for: key).appendingPathComponent("Index.json")
    }

    private func loadIndex(_ key: String) -> IconHistoryIndex {
        if let cached = indexes[key] { return cached }
        let url = indexURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(IconHistoryIndex.self, from: data) else {
            return IconHistoryIndex()
        }
        indexes[key] = decoded
        return decoded
    }

    private func saveIndex(_ key: String) {
        guard let index = indexes[key] else { return }
        do {
            try fileManager.createDirectory(at: directory(for: key), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL(for: key), options: .atomic)
        } catch {
            // 历史记录写入失败不影响主流程。
        }
    }

    private func loadSummary() {
        guard summary == nil else { return }
        if let data = try? Data(contentsOf: summaryURL),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            summary = decoded
        } else {
            summary = [:]
        }
    }

    private func saveSummary() {
        guard let summary else { return }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(summary)
            try data.write(to: summaryURL, options: .atomic)
        } catch {
            // 忽略。
        }
    }

    private static func safeName(_ key: String) -> String {
        let sanitized = key
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
        if sanitized.count <= 120 { return sanitized }
        return String(sanitized.prefix(80)) + "-" + String(hash(Data(key.utf8)).prefix(16))
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
