import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 扫描时顺带保存的图标缓存，按 Bundle ID 存放。
///
/// 应用卸载后系统里就取不到图标了。展示框只能退回快照里存的那张图，
/// 而旧快照里的图标是低分辨率放大的。所以每次扫描把当前应用的高清图标
/// 存一份到这里，卸载后仍然能显示清晰的图标。
enum IconDiskCache {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Custocub/IconCache", isDirectory: true)
    }()

    static func url(for bundleID: String) -> URL {
        let name = bundleID.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(name).appendingPathExtension("png")
    }

    static func load(bundleID: String) -> NSImage? {
        guard let data = try? Data(contentsOf: url(for: bundleID)) else { return nil }
        return NSImage(data: data)
    }

    static func store(_ data: Data, bundleID: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: bundleID), options: .atomic)
    }

    /// 缓存比应用本体新就不必重新生成；应用更新后图标可能变化。
    ///
    /// 用扫描得到的 `updatedAt`（Info.plist / 可执行文件 / bundle 的
    /// 最新修改时间）来比较，而不是只看 `.app` 目录本身。很多更新器
    /// 只替换 bundle 内的文件，目录 mtime 可能不变，旧逻辑会误判为新鲜。
    static func isFresh(bundleID: String, app: AppRecord) -> Bool {
        guard let cacheDate = modificationDate(of: url(for: bundleID)) else { return false }
        if let updatedAt = app.updatedAt {
            return cacheDate >= updatedAt
        }
        guard let appDate = modificationDate(of: URL(fileURLWithPath: app.path)) else { return true }
        return cacheDate >= appDate
    }

    static func remove(bundleID: String) {
        try? FileManager.default.removeItem(at: url(for: bundleID))
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 600
    }

    func cachedIcon(forPath path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    /// 只看内存缓存，避免渲染时同步读磁盘。
    func cachedIcon(forBundleID bundleID: String) -> NSImage? {
        cache.object(forKey: Self.bundleKey(bundleID))
    }

    /// 异步行加载图标，避免切换筛选时在 MainActor 上同步读取大量图标。
    func iconAsync(forPath path: String) async -> NSImage? {
        if let cached = cachedIcon(forPath: path) {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let image = await Task.detached(priority: .utility) {
            Self.loadIcon(forPath: path)
        }.value

        if let image {
            cache.setObject(image, forKey: path as NSString)
        }
        return image
    }

    /// 应用已卸载时，按 Bundle ID 从磁盘缓存取回图标。
    func iconAsync(forBundleID bundleID: String) async -> NSImage? {
        if let cached = cachedIcon(forBundleID: bundleID) {
            return cached
        }
        let key = Self.bundleKey(bundleID)
        let image = await Task.detached(priority: .utility) {
            IconDiskCache.load(bundleID: bundleID)
        }.value

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    /// 全量刷新时清空内存图标缓存。磁盘缓存不整体删除，
    /// 只重写当前已安装应用的条目，这样已卸载应用仍能保留自己的图标。
    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    /// 扫描完成后在后台预取图标，并把高清图标写入磁盘缓存。
    ///
    /// - Parameters:
    ///   - forceDiskRewrite: 全量刷新时置为 true，即使磁盘缓存
    ///     看起来是新的，也重新渲染并覆盖当前应用的图标。
    ///   - forcePaths: 本次扫描中发现版本/更新时间变化的应用路径，
    ///     这些应用必须重新渲染图标。
    func prefetch(
        apps: [AppRecord],
        forceDiskRewrite: Bool = false,
        forcePaths: Set<String> = []
    ) async {
        await prefetchIntoMemory(paths: apps.map(\.path))
        await storeIconsOnDisk(apps: apps, force: forceDiskRewrite, forcePaths: forcePaths)
    }

    private func prefetchIntoMemory(paths: [String]) async {
        let missing = paths.filter { cachedIcon(forPath: $0) == nil }
        guard !missing.isEmpty else { return }

        let chunkSize = 8
        var start = 0

        while start < missing.count {
            if Task.isCancelled { return }
            let end = min(start + chunkSize, missing.count)
            let chunk = Array(missing[start..<end])

            let loaded = await withTaskGroup(of: (String, NSImage?).self) { group in
                for path in chunk {
                    group.addTask {
                        (path, Self.loadIcon(forPath: path))
                    }
                }
                var results: [(String, NSImage?)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            for (path, image) in loaded {
                if let image {
                    cache.setObject(image, forKey: path as NSString)
                }
            }

            start = end
        }
    }

    /// 把当前扫描到的应用图标渲染成 192px PNG 写进缓存。
    /// 只处理新增或应用本体有更新的条目，正常启动几乎不做事。
    private func storeIconsOnDisk(
        apps: [AppRecord],
        force: Bool = false,
        forcePaths: Set<String> = []
    ) async {
        let targets: [(bundleID: String, path: String)] = apps.compactMap { app in
            guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
            if !force, !forcePaths.contains(app.path),
               IconDiskCache.isFresh(bundleID: bundleID, app: app) {
                return nil
            }
            return (bundleID, app.path)
        }
        guard !targets.isEmpty else { return }

        let chunkSize = 8
        var start = 0

        while start < targets.count {
            if Task.isCancelled { return }
            let end = min(start + chunkSize, targets.count)
            let chunk = Array(targets[start..<end])

            await withTaskGroup(of: (String, Data?).self) { group in
                for target in chunk {
                    group.addTask {
                        (target.bundleID, Self.renderPNG(forPath: target.path, pixelSize: 192))
                    }
                }
                for await (bundleID, data) in group {
                    if let data {
                        IconDiskCache.store(data, bundleID: bundleID)
                    }
                }
            }

            start = end
        }
    }

    nonisolated private static func bundleKey(_ bundleID: String) -> NSString {
        "bundle:\(bundleID)" as NSString
    }

    nonisolated private static func loadIcon(forPath path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        // 优先直接读取 bundle 里的图标文件。
        //
        // NSWorkspace 的图标服务会按路径/Bundle ID 缓存图标，应用更新后
        // 在同一个进程里可能继续返回旧图。直接读 .icns 可以绕开这层缓存。
        //
        // 系统应用例外：它们大量使用 Assets.car，目录里的 .icns 往往只是
        // 空白占位图，直接读取会得到白块，所以系统应用仍交给 NSWorkspace。
        if !path.hasPrefix("/System/"),
           let direct = directIcon(forPath: path) {
            return direct
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// 从 `.app` 的 Info.plist 和 Resources 目录查找图标文件。
    nonisolated static func directIcon(forPath path: String) -> NSImage? {
        let appURL = URL(fileURLWithPath: path)
        let resources = appURL.appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let fileManager = FileManager.default

        var candidates: [URL] = []

        func appendIcon(_ name: String) {
            guard !name.isEmpty else { return }
            let url = URL(fileURLWithPath: name)
            if url.pathExtension.isEmpty {
                candidates.append(resources.appendingPathComponent(name).appendingPathExtension("icns"))
            }
            candidates.append(resources.appendingPathComponent(name))
        }

        let infoURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: infoURL) {
            if let iconFile = info["CFBundleIconFile"] as? String {
                appendIcon(iconFile)
            }
            if let iconName = info["CFBundleIconName"] as? String {
                appendIcon(iconName)
            }
        }

        // 没有声明图标文件的应用（例如使用 Assets.car 的构建）通常
        // 仍会留下一个 AppIcon.icns 作为资源。
        for name in ["AppIcon.icns", "AppIcon.png", "app.icns", "icon.icns"] {
            candidates.append(resources.appendingPathComponent(name))
        }

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            if let image = NSImage(contentsOf: candidate) {
                return image
            }
        }
        return nil
    }

    /// 把应用图标渲染成固定尺寸 PNG，用于写入快照。
    func pngData(forPath path: String, pixelSize: CGFloat = 192) -> Data? {
        Self.renderPNG(forPath: path, pixelSize: pixelSize)
    }

    /// 并发渲染一批图标。CoreGraphics + ImageIO 可以在后台线程安全执行。
    nonisolated static func renderPNGs(for paths: [String], pixelSize: CGFloat = 192) async -> [String: Data] {
        var result: [String: Data] = [:]
        let chunkSize = 8
        var start = 0

        while start < paths.count {
            let end = min(start + chunkSize, paths.count)
            let chunk = Array(paths[start..<end])

            await withTaskGroup(of: (String, Data?).self) { group in
                for path in chunk {
                    group.addTask {
                        (path, renderPNG(forPath: path, pixelSize: pixelSize))
                    }
                }
                for await (path, data) in group {
                    if let data { result[path] = data }
                }
            }

            start = end
        }

        return result
    }

    nonisolated static func renderPNG(forPath path: String, pixelSize: CGFloat = 192) -> Data? {
        guard let source = loadIcon(forPath: path) else { return nil }
        // 直接请求目标像素的位图表示。
        //
        // 之前用 `source.size`（通常是 32pt）作为建议尺寸，系统只会给出
        // 64×64 的位图，再放大到目标尺寸就会发虚。按目标尺寸请求可以
        // 拿到 256/512 的原始位图，重采样后边缘是清晰的。
        var proposedRect = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
        guard let cgImage = source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let pixelWidth = Int(pixelSize)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelWidth,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelWidth))

        guard let scaled = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, scaled, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func invalidate(path: String) {
        cache.removeObject(forKey: path as NSString)
    }

    /// 应用更新后，清掉按路径和 Bundle ID 缓存的图标，
    /// 让 SwiftUI 重新从磁盘上的新 bundle 读取图标。
    func invalidate(apps: [AppRecord]) {
        for app in apps {
            cache.removeObject(forKey: app.path as NSString)
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
                cache.removeObject(forKey: Self.bundleKey(bundleID))
            }
        }
    }

    func clear() {
        cache.removeAllObjects()
    }
}
