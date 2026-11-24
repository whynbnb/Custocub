import AppKit
import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

/// 导出应用清单时使用的数据源。既可以是当前扫描，也可以是某个历史快照。
struct InventoryReportSource: Sendable {
    let title: String
    let apps: [AppRecord]
    let generatedAt: Date
    let capturedAt: Date
    let hostName: String
    let osVersion: String
    let note: String
    let isSnapshot: Bool

    static func snapshot(_ snapshot: AppSnapshot) -> InventoryReportSource {
        InventoryReportSource(
            title: snapshot.name,
            apps: snapshot.apps,
            generatedAt: Date(),
            capturedAt: snapshot.createdAt,
            hostName: snapshot.hostName,
            osVersion: snapshot.osVersion,
            note: snapshot.note,
            isSnapshot: true
        )
    }

    static func currentScan(apps: [AppRecord], lastScanAt: Date?) -> InventoryReportSource {
        InventoryReportSource(
            title: L.t("当前扫描"),
            apps: apps,
            generatedAt: Date(),
            capturedAt: lastScanAt ?? Date(),
            hostName: Host.current().localizedName ?? "Mac",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            note: "",
            isSnapshot: false
        )
    }
}

enum InventoryReportFormat: String, CaseIterable, Identifiable, Sendable {
    case html
    case pdf
    case csv

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .html: L.t("HTML 报告…")
        case .pdf: L.t("PDF 报告…")
        case .csv: L.t("CSV 清单…")
        }
    }

    var fileExtension: String {
        switch self {
        case .html: "html"
        case .pdf: "pdf"
        case .csv: "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .html: .html
        case .pdf: .pdf
        case .csv: .commaSeparatedText
        }
    }
}

/// 把当前应用清单渲染成可以归档或发给别人的 HTML / PDF / CSV。
enum InventoryReport {
    // MARK: - 公共数据

    private struct Summary {
        let total: Int
        let system: Int
        let thirdParty: Int
        let measuredBytes: Int64
        let missingSizes: Int
        /// 来源名称直接存字符串，便于插入「开发者的应用」这个非 AppSource 分类。
        let sources: [(title: String, count: Int)]

        var totalSizeText: String {
            measuredBytes.formatted(.byteCount(style: .file))
        }

        var sourceText: String {
            sources
                .filter { $0.count > 0 }
                .map { "\($0.title) \($0.count)" }
                .joined(separator: " · ")
        }
    }

    private static func sortedApps(_ apps: [AppRecord]) -> [AppRecord] {
        apps.sorted {
            displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    /// 少数系统应用的名称只有不可见格式字符（如 U+200E），回退到 Bundle ID。
    private static func displayName(for app: AppRecord) -> String {
        let meaningful = app.name.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator:
                return false
            default:
                return true
            }
        }
        guard meaningful else {
            return app.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? app.name
        }
        return app.name
    }

    private static func summarize(_ apps: [AppRecord]) -> Summary {
        let system = apps.count { $0.isSystemApp }
        let measured = apps.compactMap(\.sizeInBytes)
        var counts = Dictionary(grouping: apps, by: \.source).mapValues(\.count)

        // 与侧边栏保持同一口径：开启「开发者的应用」时，手动安装的
        // 开发者应用从「手动安装」中分离；关闭时仍按真实来源统计。
        let showsDeveloperApps = UserDefaults.standard
            .object(forKey: AppPreferenceKey.showDeveloperApps) as? Bool ?? true
        let developerApps = showsDeveloperApps
            ? apps.count { $0.isOwn && $0.source == .manual }
            : 0
        counts[.manual] = apps.count {
            $0.source == .manual && !(showsDeveloperApps && $0.isOwn)
        }

        var sources = AppSource.allCases.map {
            (title: $0.title, count: counts[$0] ?? 0)
        }
        if developerApps > 0 {
            sources.insert((title: L.t("开发者的应用"), count: developerApps), at: 0)
        }

        return Summary(
            total: apps.count,
            system: system,
            thirdParty: apps.count - system,
            measuredBytes: measured.reduce(0, +),
            missingSizes: apps.count - measured.count,
            sources: sources
        )
    }

    private static var isChinese: Bool {
        let code = LocalizationBundle.activeLanguage ?? AppLanguage.systemLanguageCode
        return code.hasPrefix("zh")
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - HTML

    static func html(_ source: InventoryReportSource) -> String {
        let apps = sortedApps(source.apps)
        let summary = summarize(apps)
        let generated = timestamp(source.generatedAt)
        let captured = timestamp(source.capturedAt)

        var meta = [
            L.t("生成时间：%@", generated),
            L.t("数据来源：%@", source.title)
        ]
        meta.append(L.t("扫描时间：%@", captured))
        meta.append(L.t("主机：%@", source.hostName))

        var metaLines = [
            meta.prefix(2).joined(separator: " · "),
            meta.dropFirst(2).joined(separator: " · ")
        ]
        if !source.note.isEmpty {
            metaLines.append(L.t("备注：%@", source.note))
        }

        let rows = apps.map { app in
            let bundleID = app.bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            let subtitle = bundleID.map { "<div class=\"bundle\">\(escape($0))</div>" } ?? ""
            let size = app.sizeInBytes?.formatted(.byteCount(style: .file)) ?? "—"
            let updated = app.updatedAt?.formatted(date: .numeric, time: .omitted) ?? "—"

            return """
            <tr>
              <td><div class="name">\(escape(displayName(for: app)))</div>\(subtitle)</td>
              <td>\(escape(app.displayVersion))</td>
              <td>\(escape(app.source.title))</td>
              <td>\(escape(app.platform.shortTitle))</td>
              <td>\(escape(app.typeTitle))</td>
              <td class="num">\(escape(size))</td>
              <td>\(escape(updated))</td>
            </tr>
            """
        }.joined(separator: "\n")

        let emptyRow = """
        <tr><td colspan="7" class="empty">\(escape(L.t("报告中没有应用")))</td></tr>
        """

        let missingNote = summary.missingSizes > 0
            ? "<p class=\"note\">\(escape(L.t("部分应用体积尚未测量")))</p>"
            : ""

        return """
        <!DOCTYPE html>
        <html lang="\(isChinese ? "zh-Hans" : "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(L.t("Custocub 应用清单报告")))</title>
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        /* 强制显示滚动条：macOS 默认会隐藏滚动条，长清单很难判断位置。 */
        html {
          overflow-y: scroll;
          scrollbar-color: #b0b0b8 #ececf0;
        }
        ::-webkit-scrollbar { width: 14px; height: 14px; }
        ::-webkit-scrollbar-track { background: #ececf0; }
        ::-webkit-scrollbar-thumb {
          background: #b0b0b8; border: 3px solid #ececf0; border-radius: 7px;
        }
        ::-webkit-scrollbar-thumb:hover { background: #8e8e93; }
        body {
          margin: 0; padding: 40px 32px;
          font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
          color: #1d1d1f; background: #ffffff;
        }
        .page { max-width: 1080px; margin: 0 auto; }
        h1 { margin: 0 0 8px; font-size: 28px; letter-spacing: -0.02em; }
        .meta { margin: 0 0 2px; color: #6e6e73; font-size: 12.5px; }
        .summary {
          display: flex; flex-wrap: wrap; gap: 10px;
          margin: 24px 0 10px;
        }
        .stat {
          min-width: 118px; padding: 12px 16px;
          border: 1px solid #e5e5ea; border-radius: 10px;
          background: #fafafa;
        }
        .stat span { display: block; color: #6e6e73; font-size: 11.5px; }
        .stat strong { display: block; margin-top: 3px; font-size: 20px; letter-spacing: -0.02em; }
        .source-line { margin: 6px 0 0; color: #6e6e73; font-size: 12.5px; }
        .note { margin: 6px 0 0; color: #b25000; font-size: 12px; }
        table { width: 100%; border-collapse: collapse; margin-top: 22px; font-size: 12.5px; }
        thead th {
          position: sticky; top: 0;
          text-align: left; font-weight: 600; color: #3a3a3c;
          padding: 9px 10px; background: #f2f2f7; border-bottom: 1px solid #d1d1d6;
          white-space: nowrap;
        }
        tbody td { padding: 8px 10px; border-bottom: 1px solid #ececf0; vertical-align: top; }
        tbody tr:nth-child(even) { background: #fafafa; }
        td.num { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
        .name { font-weight: 600; }
        .bundle { color: #8e8e93; font-size: 11px; margin-top: 1px; word-break: break-all; }
        .empty { text-align: center; color: #8e8e93; padding: 30px; }
        footer { margin-top: 22px; color: #8e8e93; font-size: 11.5px; }
        @media print {
          html { overflow: visible; }
          body { padding: 0; }
          .page { max-width: none; }
          thead { display: table-header-group; }
          tr { break-inside: avoid; }
          .stat { break-inside: avoid; }
        }
        </style>
        </head>
        <body>
        <div class="page">
          <h1>\(escape(L.t("Custocub 应用清单报告")))</h1>
          \(metaLines.map { "<p class=\"meta\">\(escape($0))</p>" }.joined(separator: "\n  "))

          <div class="summary">
            <div class="stat"><span>\(escape(L.t("应用总数")))</span><strong>\(summary.total)</strong></div>
            <div class="stat"><span>\(escape(L.t("系统应用")))</span><strong>\(summary.system)</strong></div>
            <div class="stat"><span>\(escape(L.t("第三方应用")))</span><strong>\(summary.thirdParty)</strong></div>
            <div class="stat"><span>\(escape(L.t("总占用")))</span><strong>\(escape(summary.totalSizeText))</strong></div>
          </div>
          <p class="source-line">\(escape(L.t("按来源：%@", summary.sourceText)))</p>
          \(missingNote)

          <table>
            <thead>
              <tr>
                <th>\(escape(L.t("应用")))</th>
                <th>\(escape(L.t("版本")))</th>
                <th>\(escape(L.t("来源")))</th>
                <th>\(escape(L.t("平台")))</th>
                <th>\(escape(L.t("类型")))</th>
                <th class="num">\(escape(L.t("大小")))</th>
                <th>\(escape(L.t("更新于")))</th>
              </tr>
            </thead>
            <tbody>
            \(rows.isEmpty ? emptyRow : rows)
            </tbody>
          </table>

          <footer>\(escape(L.t("由 Custocub 生成 · %@", timestamp(source.generatedAt))))</footer>
        </div>
        </body>
        </html>
        """
    }

    // MARK: - CSV

    static func csv(_ source: InventoryReportSource) -> String {
        let apps = sortedApps(source.apps)
        let header = [
            L.t("应用"),
            L.t("Bundle ID"),
            L.t("版本"),
            L.t("构建号"),
            L.t("来源"),
            L.t("平台"),
            L.t("架构"),
            L.t("类型"),
            L.t("大小（字节）"),
            L.t("更新于"),
            L.t("应用路径")
        ]

        var lines = [header.map(csvField).joined(separator: ",")]
        for app in apps {
            let row = [
                displayName(for: app),
                app.bundleIdentifier ?? "",
                app.version ?? "",
                app.build ?? "",
                app.source.title,
                app.platform.shortTitle,
                app.architectureText,
                app.typeTitle,
                app.sizeInBytes.map(String.init) ?? "",
                app.updatedAt.map { isoDate($0) } ?? "",
                app.path
            ]
            lines.append(row.map(csvField).joined(separator: ","))
        }

        // Excel 打开 UTF-8 CSV 时需要 BOM，否则中文会乱码。
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    // MARK: - PDF

    private static let pageWidth: CGFloat = 595
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 20
    private static let tableHeaderHeight: CGFloat = 22
    private static let firstTableTop: CGFloat = 164
    private static let continuationTableTop: CGFloat = 64
    private static let footerReserved: CGFloat = 44

    static func pdf(_ source: InventoryReportSource) -> Data {
        let apps = sortedApps(source.apps)
        let summary = summarize(apps)
        let pageRows = paginate(apps)

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        for (index, rows) in pageRows.enumerated() {
            context.beginPDFPage(nil)
            drawPage(
                context,
                rows: rows,
                pageIndex: index,
                pageCount: pageRows.count,
                source: source,
                summary: summary,
                totalApps: apps.count
            )
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private static func paginate(_ apps: [AppRecord]) -> [[AppRecord]] {
        guard !apps.isEmpty else { return [[]] }

        var result: [[AppRecord]] = []
        var index = 0
        while index < apps.count {
            let tableTop = result.isEmpty ? firstTableTop : continuationTableTop
            let capacity = rowsPerPage(tableTop: tableTop)
            let end = min(index + capacity, apps.count)
            result.append(Array(apps[index..<end]))
            index = end
        }
        return result
    }

    private static func rowsPerPage(tableTop: CGFloat) -> Int {
        let available = pageHeight - footerReserved - tableTop - tableHeaderHeight
        return max(1, Int(available / rowHeight))
    }

    private enum Column {
        static let name: CGFloat = 172
        static let version: CGFloat = 58
        static let source: CGFloat = 58
        static let platform: CGFloat = 58
        static let type: CGFloat = 40
        static let size: CGFloat = 58
        static let updated: CGFloat = 79

        static let all: [CGFloat] = [name, version, source, platform, type, size, updated]
    }

    private static func drawPage(
        _ context: CGContext,
        rows: [AppRecord],
        pageIndex: Int,
        pageCount: Int,
        source: InventoryReportSource,
        summary: Summary,
        totalApps: Int
    ) {
        let black = CGColor(gray: 0.12, alpha: 1)
        let secondary = CGColor(gray: 0.44, alpha: 1)
        let separator = CGColor(gray: 0.87, alpha: 1)
        let headerBackground = CGColor(gray: 0.95, alpha: 1)
        let zebra = CGColor(gray: 0.975, alpha: 1)

        let titleFont = systemFont(size: 20, bold: true)
        let sectionFont = systemFont(size: 10.5, bold: true)
        let bodyFont = systemFont(size: 9)
        let headerFont = systemFont(size: 8.6, bold: true)
        let rowFont = systemFont(size: 8.6)
        let footerFont = systemFont(size: 8)

        let tableTop: CGFloat
        if pageIndex == 0 {
            tableTop = firstTableTop

            drawText(
                L.t("Custocub 应用清单报告"),
                font: titleFont,
                color: black,
                x: margin,
                top: 34,
                maxWidth: pageWidth - margin * 2,
                context: context
            )

            let generated = L.t("生成时间：%@", timestamp(source.generatedAt))
            let sourceLine = L.t("数据来源：%@", source.title)
            drawText(
                "\(generated) · \(sourceLine)",
                font: bodyFont,
                color: secondary,
                x: margin,
                top: 68,
                maxWidth: pageWidth - margin * 2,
                context: context
            )

            let scanLine = [
                L.t("扫描时间：%@", timestamp(source.capturedAt)),
                L.t("主机：%@", source.hostName),
                source.osVersion
            ].joined(separator: " · ")
            drawText(
                scanLine,
                font: bodyFont,
                color: secondary,
                x: margin,
                top: 84,
                maxWidth: pageWidth - margin * 2,
                context: context
            )

            if !source.note.isEmpty {
                drawText(
                    L.t("备注：%@", source.note),
                    font: bodyFont,
                    color: secondary,
                    x: margin,
                    top: 100,
                    maxWidth: pageWidth - margin * 2,
                    context: context
                )
            }

            let summaryLine = [
                L.t("应用总数：%d", summary.total),
                L.t("系统：%d", summary.system),
                L.t("第三方：%d", summary.thirdParty),
                L.t("总占用：%@", summary.totalSizeText)
            ].joined(separator: " · ")
            drawText(
                summaryLine,
                font: sectionFont,
                color: black,
                x: margin,
                top: 118,
                maxWidth: pageWidth - margin * 2,
                context: context
            )

            drawText(
                L.t("按来源：%@", summary.sourceText),
                font: bodyFont,
                color: secondary,
                x: margin,
                top: 134,
                maxWidth: pageWidth - margin * 2,
                context: context
            )

            if summary.missingSizes > 0 {
                drawText(
                    L.t("部分应用体积尚未测量"),
                    font: bodyFont,
                    color: CGColor(red: 0.70, green: 0.32, blue: 0, alpha: 1),
                    x: margin,
                    top: 148,
                    maxWidth: pageWidth - margin * 2,
                    context: context
                )
            }
        } else {
            tableTop = continuationTableTop
            drawText(
                L.t("Custocub 应用清单报告（续）"),
                font: sectionFont,
                color: black,
                x: margin,
                top: 34,
                maxWidth: pageWidth - margin * 2,
                context: context
            )
        }

        drawTable(
            context,
            rows: rows,
            tableTop: tableTop,
            headerFont: headerFont,
            rowFont: rowFont,
            black: black,
            secondary: secondary,
            separator: separator,
            headerBackground: headerBackground,
            zebra: zebra,
            totalApps: totalApps
        )

        let footer = L.t("Custocub · 第 %d / %d 页", pageIndex + 1, pageCount)
        drawText(
            footer,
            font: footerFont,
            color: secondary,
            x: margin,
            top: pageHeight - 26,
            maxWidth: pageWidth - margin * 2,
            context: context,
            alignment: .right
        )
    }

    private enum TextAlignment {
        case left
        case right
    }

    private static func drawTable(
        _ context: CGContext,
        rows: [AppRecord],
        tableTop: CGFloat,
        headerFont: CTFont,
        rowFont: CTFont,
        black: CGColor,
        secondary: CGColor,
        separator: CGColor,
        headerBackground: CGColor,
        zebra: CGColor,
        totalApps: Int
    ) {
        let contentWidth = pageWidth - margin * 2

        fill(
            context,
            color: headerBackground,
            x: margin,
            top: tableTop,
            width: contentWidth,
            height: tableHeaderHeight
        )
        strokeLine(context, color: separator, x: margin, top: tableTop + tableHeaderHeight, width: contentWidth)

        let headers = [
            L.t("应用"),
            L.t("版本"),
            L.t("来源"),
            L.t("平台"),
            L.t("类型"),
            L.t("大小"),
            L.t("更新于")
        ]
        let headerLineHeight = lineHeight(headerFont)
        let headerTextTop = tableTop + (tableHeaderHeight - headerLineHeight) / 2
        var x = margin + 6
        for (index, title) in headers.enumerated() {
            let width = Column.all[index]
            drawText(
                title,
                font: headerFont,
                color: black,
                x: x,
                top: headerTextTop,
                maxWidth: width - 8,
                context: context,
                alignment: index == 5 ? .right : .left
            )
            x += width
        }

        if rows.isEmpty {
            drawText(
                L.t("报告中没有应用"),
                font: rowFont,
                color: secondary,
                x: margin + 6,
                top: tableTop + tableHeaderHeight + 18,
                maxWidth: contentWidth - 12,
                context: context
            )
            return
        }

        let rowLineHeight = lineHeight(rowFont)
        var rowTop = tableTop + tableHeaderHeight
        for (index, app) in rows.enumerated() {
            if index.isMultiple(of: 2) == false {
                fill(
                    context,
                    color: zebra,
                    x: margin,
                    top: rowTop,
                    width: contentWidth,
                    height: rowHeight
                )
            }

            let textTop = rowTop + (rowHeight - rowLineHeight) / 2
            let sizeText = app.sizeInBytes?.formatted(.byteCount(style: .file)) ?? "—"
            let updatedText = app.updatedAt?.formatted(date: .numeric, time: .omitted) ?? "—"
            let values = [
                displayName(for: app),
                app.displayVersion,
                app.source.shortTitle,
                app.platform.shortTitle,
                app.typeTitle,
                sizeText,
                updatedText
            ]

            var cellX = margin + 6
            for (column, value) in values.enumerated() {
                let width = Column.all[column]
                drawText(
                    value,
                    font: rowFont,
                    color: black,
                    x: cellX,
                    top: textTop,
                    maxWidth: width - 8,
                    context: context,
                    alignment: column == 5 ? .right : .left
                )
                cellX += width
            }

            strokeLine(context, color: separator, x: margin, top: rowTop + rowHeight, width: contentWidth)
            rowTop += rowHeight
        }

        // 页脚区域之前留白，避免最后一行贴住页码。
        _ = totalApps
    }

    private static func fill(
        _ context: CGContext,
        color: CGColor,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        context.setFillColor(color)
        context.fill(CGRect(x: x, y: pageHeight - top - height, width: width, height: height))
    }

    private static func strokeLine(
        _ context: CGContext,
        color: CGColor,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat
    ) {
        context.setStrokeColor(color)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: pageHeight - top))
        context.addLine(to: CGPoint(x: x + width, y: pageHeight - top))
        context.strokePath()
    }

    private static func drawText(
        _ text: String,
        font: CTFont,
        color: CGColor,
        x: CGFloat,
        top: CGFloat,
        maxWidth: CGFloat,
        context: CGContext,
        alignment: TextAlignment = .left
    ) {
        guard !text.isEmpty, maxWidth > 0 else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        var line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        var lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        if lineWidth > maxWidth {
            let token = CTLineCreateWithAttributedString(
                NSAttributedString(string: "…", attributes: attributes)
            )
            if let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end, token) {
                line = truncated
                lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            }
        }

        let drawX: CGFloat
        switch alignment {
        case .left:
            drawX = x
        case .right:
            drawX = x + maxWidth - lineWidth
        }

        let ascent = CTFontGetAscent(font)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: drawX, y: pageHeight - top - ascent)
        CTLineDraw(line, context)
    }

    private static func systemFont(size: CGFloat, bold: Bool = false) -> CTFont {
        let font = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        return CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, size, nil)
    }

    private static func lineHeight(_ font: CTFont) -> CGFloat {
        CTFontGetAscent(font) + CTFontGetDescent(font)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
