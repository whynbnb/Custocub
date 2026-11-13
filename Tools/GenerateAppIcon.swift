// Custocub 应用图标生成脚本
//
// 用法（在仓库根目录执行）：
//   swift Tools/GenerateAppIcon.swift
//
// 脚本会绘制 1024×1024 的全幅图标，并生成 macOS AppIcon 所需的
// 全部 10 个尺寸，直接写入：
//   Custocub/Resources/Assets.xcassets/AppIcon.appiconset

import AppKit
import CoreGraphics
import ImageIO

let canvas: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

ctx.translateBy(x: 0, y: canvas)
ctx.scaleBy(x: 1, y: -1)
ctx.setAllowsAntialiasing(true)
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: colorSpace, components: [r, g, b, alpha])!
}

func linearGradient(
    in path: CGPath?,
    from start: CGPoint,
    to end: CGPoint,
    colors: [CGColor],
    locations: [CGFloat]? = nil
) {
    ctx.saveGState()
    if let path {
        ctx.addPath(path)
        ctx.clip()
    }
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(
        gradient,
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

func radialGradient(
    center: CGPoint,
    radius: CGFloat,
    colors: [CGColor],
    locations: [CGFloat]? = nil
) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations)!
    ctx.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

// MARK: - 背景

linearGradient(
    in: nil,
    from: CGPoint(x: 80, y: 0),
    to: CGPoint(x: 940, y: 1024),
    colors: [color(0x1D6BFF), color(0x0B4BA8), color(0x063A4A)],
    locations: [0, 0.5, 1]
)

ctx.setBlendMode(.plusLighter)
radialGradient(
    center: CGPoint(x: 250, y: 210),
    radius: 560,
    colors: [color(0x4F9BFF, 0.66), color(0x4F9BFF, 0.20), color(0x4F9BFF, 0)]
)
radialGradient(
    center: CGPoint(x: 820, y: 840),
    radius: 520,
    colors: [color(0x14B8A6, 0.52), color(0x14B8A6, 0.16), color(0x14B8A6, 0)]
)
radialGradient(
    center: CGPoint(x: 512, y: 100),
    radius: 460,
    colors: [color(0xE0F2FE, 0.12), color(0xE0F2FE, 0)]
)
ctx.setBlendMode(.normal)

ctx.setBlendMode(.plusLighter)
radialGradient(
    center: CGPoint(x: 150, y: 950),
    radius: 480,
    colors: [color(0xF59E0B, 0.30), color(0xF59E0B, 0.08), color(0xF59E0B, 0)]
)
ctx.setBlendMode(.normal)

// MARK: - 应用卡片

let cardRect = CGRect(x: 126, y: 292, width: 640, height: 500)
let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 96, cornerHeight: 96, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 20), blur: 44, color: color(0x000000, 0.5))
ctx.addPath(cardPath)
ctx.setFillColor(color(0xEAF6FF, 0.2))
ctx.fillPath()
ctx.restoreGState()

linearGradient(
    in: cardPath,
    from: CGPoint(x: cardRect.minX, y: cardRect.minY),
    to: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
    colors: [color(0xFFFFFF, 0.46), color(0xD6EEFF, 0.28), color(0x7CC4FF, 0.20)]
)

ctx.saveGState()
ctx.addPath(cardPath)
ctx.clip()
radialGradient(
    center: CGPoint(x: cardRect.minX + 150, y: cardRect.minY + 120),
    radius: 380,
    colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)]
)
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(cardPath)
ctx.setLineWidth(6)
ctx.setStrokeColor(color(0xFFFFFF, 0.62))
ctx.strokePath()
ctx.restoreGState()

// MARK: - 应用格

let tileSize: CGFloat = 148
let gap: CGFloat = 36
let columns = 3
let rows = 2
let gridWidth = CGFloat(columns) * tileSize + CGFloat(columns - 1) * gap
let gridHeight = CGFloat(rows) * tileSize + CGFloat(rows - 1) * gap
let gridX = cardRect.midX - gridWidth / 2
let gridY = cardRect.midY - gridHeight / 2

func drawBeerMug(in rect: CGRect) {
    // 整体（含把手）在格子里居中。
    let bodyX = rect.midX - 36
    let bodyY = rect.midY - 39
    let width: CGFloat = 56
    let height: CGFloat = 96
    let inset: CGFloat = 4
    let radius: CGFloat = 9

    // 杯身：上宽下窄的玻璃杯。
    let body = CGMutablePath()
    body.move(to: CGPoint(x: bodyX + radius, y: bodyY))
    body.addLine(to: CGPoint(x: bodyX + width - radius, y: bodyY))
    body.addQuadCurve(
        to: CGPoint(x: bodyX + width, y: bodyY + radius),
        control: CGPoint(x: bodyX + width, y: bodyY)
    )
    body.addLine(to: CGPoint(x: bodyX + width - inset, y: bodyY + height - radius))
    body.addQuadCurve(
        to: CGPoint(x: bodyX + width - inset - radius, y: bodyY + height),
        control: CGPoint(x: bodyX + width - inset, y: bodyY + height)
    )
    body.addLine(to: CGPoint(x: bodyX + inset + radius, y: bodyY + height))
    body.addQuadCurve(
        to: CGPoint(x: bodyX + inset, y: bodyY + height - radius),
        control: CGPoint(x: bodyX + inset, y: bodyY + height)
    )
    body.addLine(to: CGPoint(x: bodyX, y: bodyY + radius))
    body.addQuadCurve(
        to: CGPoint(x: bodyX + radius, y: bodyY),
        control: CGPoint(x: bodyX, y: bodyY)
    )
    body.closeSubpath()

    // 把手：贴在杯壁上的 D 形环。
    let rx = bodyX + width
    let handleCenterY = bodyY + height * 0.56
    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: rx - 10, y: handleCenterY - 24))
    handle.addCurve(
        to: CGPoint(x: rx + 16, y: handleCenterY),
        control1: CGPoint(x: rx + 12, y: handleCenterY - 24),
        control2: CGPoint(x: rx + 16, y: handleCenterY - 12)
    )
    handle.addCurve(
        to: CGPoint(x: rx - 10, y: handleCenterY + 24),
        control1: CGPoint(x: rx + 16, y: handleCenterY + 12),
        control2: CGPoint(x: rx + 12, y: handleCenterY + 24)
    )
    handle.closeSubpath()

    handle.move(to: CGPoint(x: rx - 10, y: handleCenterY - 12))
    handle.addCurve(
        to: CGPoint(x: rx + 7, y: handleCenterY),
        control1: CGPoint(x: rx + 4, y: handleCenterY - 12),
        control2: CGPoint(x: rx + 7, y: handleCenterY - 5)
    )
    handle.addCurve(
        to: CGPoint(x: rx - 10, y: handleCenterY + 12),
        control1: CGPoint(x: rx + 7, y: handleCenterY + 5),
        control2: CGPoint(x: rx + 4, y: handleCenterY + 12)
    )
    handle.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 8, color: color(0x8A4B00, 0.3))
    ctx.addPath(handle)
    ctx.setFillColor(color(0xE8A21A))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(handle)
    ctx.clip(using: .evenOdd)
    linearGradient(
        in: nil,
        from: CGPoint(x: rx - 10, y: handleCenterY - 24),
        to: CGPoint(x: rx + 16, y: handleCenterY + 24),
        colors: [color(0xFFD766), color(0xD98E0B)]
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(handle)
    ctx.setLineWidth(2)
    ctx.setStrokeColor(color(0xFFFFFF, 0.5))
    ctx.strokePath()
    ctx.restoreGState()

    // 杯身阴影与啤酒填充。
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 5), blur: 10, color: color(0x8A4B00, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0xD98E0B))
    ctx.fillPath()
    ctx.restoreGState()

    linearGradient(
        in: body,
        from: CGPoint(x: bodyX + width / 2, y: bodyY),
        to: CGPoint(x: bodyX + width / 2, y: bodyY + height),
        colors: [color(0xFFD65C), color(0xE9A11A), color(0xB96604)]
    )

    // 圆柱形明暗。
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    linearGradient(
        in: nil,
        from: CGPoint(x: bodyX, y: bodyY),
        to: CGPoint(x: bodyX + width, y: bodyY),
        colors: [color(0xFFFFFF, 0.30), color(0xFFFFFF, 0), color(0x000000, 0.16)]
    )
    ctx.restoreGState()

    // 气泡。
    ctx.setFillColor(color(0xFFFFFF, 0.5))
    for (bx, by, br) in [(14.0, 28.0, 3.0), (34.0, 42.0, 2.2), (24.0, 64.0, 2.6), (38.0, 72.0, 1.8)] {
        ctx.addEllipse(in: CGRect(
            x: bodyX + bx - br,
            y: bodyY + by - br,
            width: br * 2,
            height: br * 2
        ))
        ctx.fillPath()
    }

    // 杯身描边。
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.strokePath()
    ctx.restoreGState()

    // 泡沫。
    let foamY = bodyY - 2
    let foam = CGMutablePath()
    foam.addEllipse(in: CGRect(x: bodyX - 2, y: foamY - 14, width: 30, height: 28))
    foam.addEllipse(in: CGRect(x: bodyX + 16, y: foamY - 18, width: 34, height: 32))
    foam.addEllipse(in: CGRect(x: bodyX + width - 26, y: foamY - 13, width: 28, height: 26))
    foam.addRoundedRect(
        in: CGRect(x: bodyX - 2, y: foamY, width: width + 4, height: 16),
        cornerWidth: 8,
        cornerHeight: 8
    )

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 8, color: color(0x8A4B00, 0.25))
    ctx.addPath(foam)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(foam)
    ctx.clip()
    linearGradient(
        in: nil,
        from: CGPoint(x: bodyX, y: foamY - 18),
        to: CGPoint(x: bodyX, y: foamY + 16),
        colors: [color(0xFFFFFF), color(0xF0FAFF, 0.98)]
    )
    ctx.restoreGState()

    // 泡沫高光。
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    ctx.addEllipse(in: CGRect(x: bodyX + 7, y: foamY - 14, width: 18, height: 12))
    ctx.fillPath()

    ctx.saveGState()
    ctx.addPath(foam)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.strokePath()
    ctx.restoreGState()
}

for row in 0..<rows {
    for column in 0..<columns {
        let rect = CGRect(
            x: gridX + CGFloat(column) * (tileSize + gap),
            y: gridY + CGFloat(row) * (tileSize + gap),
            width: tileSize,
            height: tileSize
        )
        let path = CGPath(roundedRect: rect, cornerWidth: 38, cornerHeight: 38, transform: nil)
        let index = row * columns + column
        let tint: (top: UInt32, bottom: UInt32, shadow: UInt32)? = switch index {
        case 1: (0xD1FAE5, 0xA7F3D0, 0x10B981)
        case 5: (0xFFE4E6, 0xFECDD3, 0xFB7185)
        default: nil
        }

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 9),
            blur: 22,
            color: tint.map { color($0.shadow, 0.4) } ?? color(0x0A3D91, 0.45)
        )
        ctx.addPath(path)
        ctx.setFillColor(color(0xEAF6FF, 0.92))
        ctx.fillPath()
        ctx.restoreGState()

        if let tint {
            linearGradient(
                in: path,
                from: CGPoint(x: rect.midX, y: rect.minY),
                to: CGPoint(x: rect.midX, y: rect.maxY),
                colors: [color(tint.top, 0.95), color(tint.bottom, 0.9)]
            )
        } else {
            linearGradient(
                in: path,
                from: CGPoint(x: rect.midX, y: rect.minY),
                to: CGPoint(x: rect.midX, y: rect.maxY),
                colors: [color(0xFFFFFF, 0.98), color(0xD8ECFF, 0.82)]
            )
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        linearGradient(
            in: nil,
            from: CGPoint(x: rect.midX, y: rect.minY),
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.55),
            colors: [color(0xFFFFFF, 0.55), color(0xFFFFFF, 0.05), color(0xFFFFFF, 0)]
        )
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.addPath(path)
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(color(0xFFFFFF, 0.8))
        ctx.strokePath()
        ctx.restoreGState()

        if row == 1 && column == 0 {
            drawBeerMug(in: rect)
        }
    }
}

// MARK: - 放大镜

let lensCenter = CGPoint(x: 742, y: 272)
let ringRadius: CGFloat = 138
let ringWidth: CGFloat = 46
let lensRadius = ringRadius - ringWidth / 2 + 1

// 镜片色调
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius,
    y: lensCenter.y - lensRadius,
    width: lensRadius * 2,
    height: lensRadius * 2
))
ctx.clip()
radialGradient(
    center: CGPoint(x: lensCenter.x - 30, y: lensCenter.y - 40),
    radius: lensRadius * 1.5,
    colors: [color(0xE0F7FF, 0.24), color(0x38BDF8, 0.22), color(0x083A73, 0.36)]
)
linearGradient(
    in: nil,
    from: CGPoint(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius),
    to: CGPoint(x: lensCenter.x + lensRadius, y: lensCenter.y + lensRadius),
    colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0.03), color(0xFFFFFF, 0)]
)
ctx.restoreGState()

// 镜片高光
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius + 14,
    y: lensCenter.y - lensRadius + 14,
    width: lensRadius * 2 - 28,
    height: lensRadius * 2 - 28
))
ctx.clip()
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius,
    y: lensCenter.y - lensRadius,
    width: lensRadius * 2,
    height: lensRadius * 2
))
ctx.clip()

// 内圈左上方的细反光。
ctx.addArc(
    center: lensCenter,
    radius: lensRadius - 20,
    startAngle: .pi * 1.03,
    endAngle: .pi * 1.52,
    clockwise: false
)
ctx.setLineWidth(10)
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xFFFFFF, 0.5))
ctx.strokePath()

// 高光点。
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - 46,
    y: lensCenter.y - 58,
    width: 10,
    height: 10
))
ctx.setFillColor(color(0xFFFFFF, 0.7))
ctx.fillPath()
ctx.restoreGState()
ctx.restoreGState()

// 手柄
let handleStart = CGPoint(x: 848, y: 378)
let handleEnd = CGPoint(x: 948, y: 478)
let handlePath = CGMutablePath()
handlePath.move(to: handleStart)
handlePath.addLine(to: handleEnd)

ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineWidth(46)
ctx.setStrokeColor(color(0x0A2A5C, 0.45))
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 26, color: color(0x000000, 0.35))
ctx.addPath(handlePath)
ctx.strokePath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(handlePath)
ctx.setLineCap(.round)
ctx.setLineWidth(46)
ctx.replacePathWithStrokedPath()
ctx.clip()
linearGradient(
    in: nil,
    from: handleStart,
    to: handleEnd,
    colors: [color(0xFFFFFF), color(0xDCEFFF), color(0xA9D3F7)]
)
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(handlePath)
ctx.setLineCap(.round)
ctx.setLineWidth(46)
ctx.replacePathWithStrokedPath()
ctx.clip()
linearGradient(
    in: nil,
    from: CGPoint(x: handleStart.x, y: handleStart.y - 14),
    to: CGPoint(x: handleStart.x, y: handleStart.y + 20),
    colors: [color(0xFFFFFF, 0.7), color(0xFFFFFF, 0)]
)
ctx.restoreGState()

// 镜框外发光
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - ringRadius,
    y: lensCenter.y - ringRadius,
    width: ringRadius * 2,
    height: ringRadius * 2
))
ctx.setLineWidth(ringWidth + 12)
ctx.setStrokeColor(color(0x9BDBFF, 0.22))
ctx.setShadow(offset: .zero, blur: 34, color: color(0x38BDF8, 0.45))
ctx.strokePath()
ctx.restoreGState()

// 镜框
let ringRect = CGRect(
    x: lensCenter.x - ringRadius,
    y: lensCenter.y - ringRadius,
    width: ringRadius * 2,
    height: ringRadius * 2
)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 16), blur: 34, color: color(0x001A3A, 0.45))
ctx.addEllipse(in: ringRect)
ctx.setLineWidth(ringWidth)
ctx.setStrokeColor(color(0xF4FAFF))
ctx.strokePath()
ctx.restoreGState()

// 镜框底部轻微冷色过渡。
ctx.saveGState()
ctx.addEllipse(in: ringRect)
ctx.setLineWidth(ringWidth)
ctx.replacePathWithStrokedPath()
ctx.clip()
linearGradient(
    in: nil,
    from: CGPoint(x: lensCenter.x, y: lensCenter.y - ringRadius),
    to: CGPoint(x: lensCenter.x, y: lensCenter.y + ringRadius),
    colors: [color(0xFFFFFF, 0), color(0x9FC8EA, 0.28)]
)
ctx.restoreGState()

// 镜框内侧高光
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - lensRadius,
    y: lensCenter.y - lensRadius,
    width: lensRadius * 2,
    height: lensRadius * 2
))
ctx.setLineWidth(4)
ctx.setStrokeColor(color(0xFFFFFF, 0.8))
ctx.strokePath()
ctx.restoreGState()

// MARK: - 输出

let scriptURL = URL(fileURLWithPath: #filePath)
let repoRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputDirectory = repoRoot
    .appendingPathComponent("Custocub/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

try? FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let baseImage = ctx.makeImage()!

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "GenerateAppIcon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)

    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "GenerateAppIcon", code: 2)
    }
}

for entry in sizes {
    let pixels = entry.pixels
    let target = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    target.interpolationQuality = .high
    target.setAllowsAntialiasing(true)
    target.draw(
        baseImage,
        in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
    )

    guard let scaled = target.makeImage() else {
        throw NSError(domain: "GenerateAppIcon", code: 3)
    }

    do {
        try writePNG(
            scaled,
            to: outputDirectory.appendingPathComponent(entry.name, isDirectory: false)
        )
    } catch {
        FileHandle.standardError.write(Data("failed to write \(entry.name)\n".utf8))
        exit(1)
    }
    print("wrote \(entry.name) (\(pixels)×\(pixels))")
}

print("AppIcon generated at \(outputDirectory.path)")
