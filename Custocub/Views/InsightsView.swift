import Charts
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: CustocubStore

    private struct TimelinePoint: Identifiable {
        let id: String
        let date: Date
        let count: Int
        let bytes: Int64
    }

    private struct CountItem: Identifiable {
        let id: String
        let name: String
        let count: Int
        let color: Color
    }

    private struct SizeItem: Identifiable {
        let id: String
        let name: String
        let bytes: Int64
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metrics

                if store.apps.isEmpty && store.snapshots.isEmpty {
                    ContentUnavailableView(
                        "还没有可统计的数据",
                        systemImage: "chart.xyaxis.line",
                        description: Text("先扫描一次应用，或保存一个快照。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 380), spacing: 16)],
                        spacing: 16
                    ) {
                        timelineCard
                        sizeCard
                        sourceCard
                        platformCard
                        largestCard
                        oldestCard
                    }
                }
            }
            .padding(18)
        }
        .navigationTitle("洞察")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("收藏柜洞察")
                .font(.title2.weight(.semibold))
            Text("基于当前扫描和历史快照的只读统计。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var metrics: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
            spacing: 10
        ) {
            InsightMetric(title: "应用", value: "\(store.apps.count)", symbol: "square.grid.2x2", color: .accentColor)
            InsightMetric(title: "总体积", value: totalSizeText, symbol: "internaldrive", color: .blue)
            InsightMetric(title: "快照", value: "\(store.snapshots.count)", symbol: "camera", color: .orange)
            InsightMetric(title: "图标变化", value: "\(iconChangeCount)", symbol: "photo.stack", color: .purple)
            InsightMetric(title: "展示框", value: "\(store.galleryItems.count)", symbol: "rectangle.grid.2x2", color: .teal)
        }
    }

    private var timelineCard: some View {
        SectionCard(title: "应用数量变化") {
            if timeline.count < 2 {
                Text("保存更多快照后，这里会显示应用数量的变化趋势。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 170)
            } else {
                Chart(timeline) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("应用", point.count)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("应用", point.count)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("应用", point.count)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(22)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var sizeCard: some View {
        SectionCard(title: "总体积变化") {
            if timeline.count < 2 {
                Text("保存更多快照后，这里会显示体积的变化趋势。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 170)
            } else {
                Chart(timeline) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("GB", Double(point.bytes) / 1_000_000_000)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.28), .blue.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("GB", Double(point.bytes) / 1_000_000_000)
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let gb = value.as(Double.self) {
                                Text(gb.formatted(.number.precision(.fractionLength(0...1))) + " GB")
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var sourceCard: some View {
        SectionCard(title: "来源分布") {
            Chart(sourceItems) { item in
                BarMark(
                    x: .value("应用", item.count),
                    y: .value("来源", item.name)
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(140, sourceItems.count * 26)))
        }
    }

    private var platformCard: some View {
        SectionCard(title: "平台分布") {
            Chart(platformItems) { item in
                BarMark(
                    x: .value("应用", item.count),
                    y: .value("平台", item.name)
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(max(140, platformItems.count * 28)))
        }
    }

    private var largestCard: some View {
        SectionCard(title: "体积最大的应用") {
            if largestApps.isEmpty {
                Text("还没有测量应用体积。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                Chart(largestApps) { item in
                    BarMark(
                        x: .value("大小", item.bytes),
                        y: .value("应用", item.name)
                    )
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(item.bytes.formatted(.byteCount(style: .file)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(max(170, largestApps.count * 26)))
            }
        }
    }

    private var oldestCard: some View {
        SectionCard(title: "最早安装的应用") {
            if oldestApps.isEmpty {
                Text("还没有可用的安装时间。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(oldestApps.enumerated()), id: \.element.id) { index, app in
                        HStack(spacing: 9) {
                            AppIconView(app: app, size: 28)
                            Text(app.name)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            if let installedAt = app.installedAt {
                                Text(installedAt, format: .dateTime.year().month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)

                        if index != oldestApps.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var timeline: [TimelinePoint] {
        var points = store.snapshots
            .sorted { $0.createdAt < $1.createdAt }
            .map { snapshot in
                TimelinePoint(
                    id: snapshot.id.uuidString,
                    date: snapshot.createdAt,
                    count: snapshot.apps.count,
                    bytes: snapshot.apps.compactMap(\.sizeInBytes).reduce(0, +)
                )
            }

        if store.hasScanned {
            points.append(TimelinePoint(
                id: "today",
                date: store.lastScanAt ?? Date(),
                count: store.apps.count,
                bytes: measuredAppsSize
            ))
        }
        return points
    }

    private var sourceItems: [CountItem] {
        let counts = Dictionary(grouping: store.apps, by: \.source).mapValues(\.count)
        return AppSource.allCases.compactMap { source in
            guard let count = counts[source], count > 0 else { return nil }
            return CountItem(id: source.rawValue, name: source.shortTitle, count: count, color: source.color)
        }
        .sorted { $0.count > $1.count }
    }

    private var platformItems: [CountItem] {
        let counts = Dictionary(grouping: store.apps, by: \.platform).mapValues(\.count)
        return AppPlatform.allCases.compactMap { platform in
            guard let count = counts[platform], count > 0 else { return nil }
            return CountItem(id: platform.rawValue, name: platform.shortTitle, count: count, color: platform.color)
        }
        .sorted { $0.count > $1.count }
    }

    private var largestApps: [SizeItem] {
        store.apps.compactMap { app in
            guard let size = app.sizeInBytes else { return nil }
            return SizeItem(id: app.id, name: app.name, bytes: size)
        }
        .sorted { $0.bytes > $1.bytes }
        .prefix(8)
        .map { $0 }
    }

    private var oldestApps: [AppRecord] {
        store.apps
            .filter { $0.installedAt != nil }
            .sorted { ($0.installedAt ?? .distantPast) < ($1.installedAt ?? .distantPast) }
            .prefix(8)
            .map { $0 }
    }

    private var measuredAppsSize: Int64 {
        store.apps.compactMap(\.sizeInBytes).reduce(0, +)
    }

    private var totalSizeText: String {
        measuredAppsSize.formatted(.byteCount(style: .file))
    }

    private var iconChangeCount: Int {
        store.apps.count { store.iconHistory(for: $0).count > 1 }
    }
}

private struct InsightMetric: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
