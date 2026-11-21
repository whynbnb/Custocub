import AppKit
import SwiftUI

/// 展示单个应用的历史图标。用于展示框的「查看图标历史」窗口。
struct IconHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppRecord

    @State private var entries: [IconHistoryEntry] = []
    @State private var isLoading = true

    private var historyKey: String { IconHistoryStore.key(for: app) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 460)
        .task(id: historyKey) {
            await load()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconView(app: app, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("图标历史")
                    .font(.title3.weight(.semibold))
                Text(L.t("共 %d 个图标版本", entries.count))
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
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            ContentUnavailableView(
                "还没有图标更新记录",
                systemImage: "photo.stack",
                description: Text("当检测到图标变化时，旧图标会保留在这里。")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(entries.reversed())) { entry in
                        IconHistoryRow(
                            historyKey: historyKey,
                            entry: entry,
                            isCurrent: entry.id == entries.last?.id
                        )
                    }
                }
                .padding(18)
            }
        }
    }

    private func load() async {
        isLoading = true
        let entries = await IconHistoryStore.shared.entries(forKey: historyKey)
        guard !Task.isCancelled else { return }
        self.entries = entries
        isLoading = false
    }
}

/// 应用详情里的横向图标时间线。
struct IconHistoryStrip: View {
    let app: AppRecord
    let entries: [IconHistoryEntry]

    private var historyKey: String { IconHistoryStore.key(for: app) }

    var body: some View {
        SectionCard(title: "图标历史") {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(entries.reversed().enumerated()), id: \.element.id) { index, entry in
                        VStack(spacing: 6) {
                            HistoryIconView(
                                historyKey: historyKey,
                                entry: entry,
                                size: 64,
                                cornerRadius: 14
                            )

                            Text(entry.capturedAt, format: .dateTime.year().month().day())
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(iconLabel(for: entry, isCurrent: index == 0))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(iconLabelColor(for: entry, isCurrent: index == 0))
                        }
                        .frame(width: 86)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        }
    }

    private func iconLabel(for entry: IconHistoryEntry, isCurrent: Bool) -> String {
        if isCurrent { return L.t("当前") }
        return entry.isBaseline ? L.t("初始图标") : L.t("更新")
    }

    private func iconLabelColor(for entry: IconHistoryEntry, isCurrent: Bool) -> Color {
        if isCurrent { return .green }
        return entry.isBaseline ? .secondary : .orange
    }
}

private struct IconHistoryRow: View {
    let historyKey: String
    let entry: IconHistoryEntry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            HistoryIconView(historyKey: historyKey, entry: entry, size: 58, cornerRadius: 13)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.isBaseline ? L.t("初始图标") : L.t("图标更新"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(entry.isBaseline ? .secondary : Color.orange)

                    if isCurrent {
                        Text("当前")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(L.t("版本 %@", entry.version ?? L.t("未知")))
                    if let build = entry.build, !build.isEmpty {
                        Text(L.t("构建号 %@", build))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(entry.capturedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 从 IconHistoryStore 异步加载单张历史图标。
struct HistoryIconView: View {
    let historyKey: String
    let entry: IconHistoryEntry
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 12

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
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
                    .background(
                        Color.secondary.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: cornerRadius)
                    )
            }
        }
        .frame(width: size, height: size)
        .task(id: entry.id) {
            guard let data = await IconHistoryStore.shared.imageData(for: entry, key: historyKey) else {
                return
            }
            image = NSImage(data: data)
        }
    }
}
