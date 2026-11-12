import Foundation

struct CachedAppSize: Codable, Sendable {
    var size: Int64
    var updatedAt: TimeInterval?
    var installedAt: TimeInterval?
    var cachedAt: TimeInterval
}

/// 体积缓存：按应用解析路径保存体积，并在应用更新时间/安装时间变化或超过 TTL 后失效。
struct SizeCache: Sendable {
    static let ttl: TimeInterval = 7 * 24 * 60 * 60

    static let defaultFileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent("size-cache.json")
    }()

    private(set) var entries: [String: CachedAppSize]
    let fileURL: URL?

    init(fileURL: URL? = SizeCache.defaultFileURL, entries: [String: CachedAppSize] = [:]) {
        self.fileURL = fileURL
        self.entries = entries
    }

    static func load(fileURL: URL = SizeCache.defaultFileURL) -> SizeCache {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: CachedAppSize].self, from: data) else {
            return SizeCache(fileURL: fileURL)
        }
        return SizeCache(fileURL: fileURL, entries: decoded)
    }

    func size(for app: AppRecord, now: Date = Date()) -> Int64? {
        guard let entry = entries[app.resolvedPath] else { return nil }
        guard FileManager.default.fileExists(atPath: app.resolvedPath) else { return nil }
        guard now.timeIntervalSince1970 - entry.cachedAt <= Self.ttl else { return nil }

        if let updatedAt = app.updatedAt {
            guard let cachedUpdated = entry.updatedAt,
                  abs(cachedUpdated - updatedAt.timeIntervalSince1970) < 1 else {
                return nil
            }
        }

        if let installedAt = app.installedAt {
            guard let cachedInstalled = entry.installedAt,
                  abs(cachedInstalled - installedAt.timeIntervalSince1970) < 1 else {
                return nil
            }
        }

        return entry.size
    }

    mutating func update(app: AppRecord, size: Int64, now: Date = Date()) {
        entries[app.resolvedPath] = CachedAppSize(
            size: size,
            updatedAt: app.updatedAt?.timeIntervalSince1970,
            installedAt: app.installedAt?.timeIntervalSince1970,
            cachedAt: now.timeIntervalSince1970
        )
    }

    mutating func prune(validPaths: Set<String>) {
        entries = entries.filter { validPaths.contains($0.key) }
    }

    func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("[Custocub] 无法保存体积缓存: \(error)")
        }
    }

    func removeFile() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
