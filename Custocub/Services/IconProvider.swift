import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

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

    /// 扫描完成后在后台预取图标，让「全部来源」等大列表切换时直接命中缓存。
    func prefetch(paths: [String]) async {
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

    nonisolated private static func loadIcon(forPath path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    /// 把应用图标渲染成固定尺寸 PNG，用于写入快照。
    func pngData(forPath path: String, pixelSize: CGFloat = 128) -> Data? {
        Self.renderPNG(forPath: path, pixelSize: pixelSize)
    }

    /// 并发渲染一批图标。CoreGraphics + ImageIO 可以在后台线程安全执行。
    nonisolated static func renderPNGs(for paths: [String], pixelSize: CGFloat = 128) async -> [String: Data] {
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

    nonisolated static func renderPNG(forPath path: String, pixelSize: CGFloat = 128) -> Data? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let source = NSWorkspace.shared.icon(forFile: path)
        var proposedRect = NSRect(origin: .zero, size: source.size)
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

    func clear() {
        cache.removeAllObjects()
    }
}
