import AppKit
import CryptoKit
import Foundation

/// 快照图标的按需读取层。
///
/// 快照原文仍保留完整 PNG，便于导出和旧版本兼容；应用运行时只读取
/// 派生缓存里的元数据。真正需要某个图标时，再从这里的 PNG 侧车文件加载。
enum SnapshotIconStore {
    static let rootDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("Custocub", isDirectory: true)
            .appendingPathComponent("SnapshotCache", isDirectory: true)
            .appendingPathComponent("Icons", isDirectory: true)
    }()

    // NSCache 本身线程安全；这里只读共享引用，用 nonisolated(unsafe) 明确标注。
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func fingerprint(for data: Data) -> String {
        guard !data.isEmpty else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fileURL(snapshotID: UUID, app: AppRecord, root: URL = rootDirectory) -> URL {
        let name = fingerprint(for: Data(app.bundleKey.utf8))
        return root
            .appendingPathComponent(snapshotID.uuidString, isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension("png")
    }

    static func store(
        _ data: Data,
        snapshotID: UUID,
        app: AppRecord,
        root: URL = rootDirectory
    ) throws {
        guard !data.isEmpty else { return }
        let url = fileURL(snapshotID: snapshotID, app: app, root: root)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func iconData(
        snapshotID: UUID,
        app: AppRecord,
        root: URL = rootDirectory
    ) -> Data? {
        if let data = app.iconData, !data.isEmpty { return data }
        let url = fileURL(snapshotID: snapshotID, app: app, root: root)
        return try? Data(contentsOf: url)
    }

    static func icon(snapshotID: UUID, app: AppRecord) -> NSImage? {
        let key = cacheKey(snapshotID: snapshotID, app: app)
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = iconData(snapshotID: snapshotID, app: app),
              let image = NSImage(data: data) else { return nil }
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        cache.setObject(image, forKey: key, cost: width * height * 4)
        return image
    }

    static func iconAsync(snapshotID: UUID, app: AppRecord) async -> NSImage? {
        if let cached = cachedIcon(snapshotID: snapshotID, app: app) { return cached }
        let data = await Task.detached(priority: .utility) {
            SnapshotIconStore.iconData(snapshotID: snapshotID, app: app)
        }.value
        guard let data, let image = NSImage(data: data) else { return nil }
        let width = max(Int(image.size.width), 1)
        let height = max(Int(image.size.height), 1)
        cache.setObject(image, forKey: cacheKey(snapshotID: snapshotID, app: app), cost: width * height * 4)
        return image
    }

    static func cachedIcon(snapshotID: UUID, app: AppRecord) -> NSImage? {
        cache.object(forKey: cacheKey(snapshotID: snapshotID, app: app))
    }

    static func remove(snapshotID: UUID, root: URL = rootDirectory) {
        try? FileManager.default.removeItem(
            at: root.appendingPathComponent(snapshotID.uuidString, isDirectory: true)
        )
        invalidateMemoryCache()
    }

    static func invalidateMemoryCache() {
        cache.removeAllObjects()
    }

    private static func cacheKey(snapshotID: UUID, app: AppRecord) -> NSString {
        "\(snapshotID.uuidString)|\(app.bundleKey)" as NSString
    }
}
