import AppKit
import SwiftUI

/// 展示单个应用在历史快照中的图标变化。
struct IconHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CustocubStore
    let app: AppRecord

    private var entries: [AppIconHistoryEntry] {
        store.iconHistory(for: app)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(app: app, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("图标历史")
                    .font(.title3.weight(.semibold))
                Text(L.t("共 %d 个快照图标版本", entries.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "还没有快照图标记录",
                systemImage: "camera",
                description: Text("保存快照后会记录图标；这里只展示不同快照之间的图标变化。")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                        IconHistoryRow(
                            entry: entry,
                            isCurrent: index == 0,
                            isFirst: index == entries.count - 1
                        )
                    }
                }
                .padding(18)
            }
        }
    }
}

/// 应用详情里的横向图标时间线。
struct IconHistoryStrip: View {
    let entries: [AppIconHistoryEntry]

    var body: some View {
        SectionCard(title: "图标历史") {
            Text("来自历史快照，只显示图标发生变化的快照。")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                        let isCurrent = index == 0
                        let isFirst = index == entries.count - 1
                        VStack(spacing: 6) {
                            HistoryIconView(iconData: entry.iconData, size: 64, cornerRadius: 14)

                            Text(entry.capturedAt, format: .dateTime.year().month().day())
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(iconLabel(isCurrent: isCurrent, isFirst: isFirst))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(iconLabelColor(isCurrent: isCurrent, isFirst: isFirst))
                        }
                        .frame(width: 86)
                        .help(Text(L.t("快照「%@」", entry.snapshotName)))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        }
    }

    private func iconLabel(isCurrent: Bool, isFirst: Bool) -> String {
        if isCurrent { return L.t("最新快照") }
        return isFirst ? L.t("初始图标") : L.t("更新")
    }

    private func iconLabelColor(isCurrent: Bool, isFirst: Bool) -> Color {
        if isCurrent { return .green }
        return isFirst ? .secondary : .orange
    }
}

private struct IconHistoryRow: View {
    let entry: AppIconHistoryEntry
    let isCurrent: Bool
    let isFirst: Bool

    var body: some View {
        HStack(spacing: 14) {
            HistoryIconView(iconData: entry.iconData, size: 58, cornerRadius: 13)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(isFirst ? L.t("初始图标") : L.t("图标更新"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isFirst ? .secondary : Color.orange)

                    if isCurrent {
                        Text("最新快照")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                Text(L.t("快照「%@」· %@", entry.snapshotName, entry.capturedAt.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(L.t("版本 %@", entry.version ?? L.t("未知")))
                    if let build = entry.build, !build.isEmpty {
                        Text(L.t("构建号 %@", build))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 直接展示快照中保存的图标。
struct HistoryIconView: View {
    let iconData: Data
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let image = NSImage(data: iconData) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.22)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(
            Color.secondary.opacity(0.1),
            in: RoundedRectangle(cornerRadius: cornerRadius)
        )
    }
}
