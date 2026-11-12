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

    func icon(forPath path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: key)
        return image
    }

    func icon(for app: AppRecord) -> NSImage? {
        // 已安装时优先使用磁盘上的最新图标；应用被卸载后回退到快照中的 PNG。
        if let image = icon(forPath: app.path) {
            return image
        }
        if let data = app.iconData, let image = NSImage(data: data) {
            return image
        }
        return nil
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
