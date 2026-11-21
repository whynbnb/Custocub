import AppKit
import SwiftUI

/// 从历史快照汇总出的应用档案：首次/最后出现、版本、来源和图标变化。
struct AppStorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CustocubStore
    let app: AppRecord

    private var story: AppStory {
        store.appStory(for: app)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary

                    if story.totalSnapshots == 0 {
                        SectionCard(title: "应用档案") {
                            Text("还没有保存过快照。保存快照后，这里会汇总这个应用的历史变化。")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        versionTimeline
                        if story.sourceChanges.count > 1 {
                            sourceChanges
                        }
                        if story.iconHistory.count > 1 {
                            IconHistoryStrip(entries: story.iconHistory)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppIconView(app: app, size: 54, cornerRadius: 13)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.title2.weight(.semibold))
                Text(app.displayBundleIdentifier)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            GalleryStatusBadge(status: story.isCurrentlyInstalled ? .installed : .uninstalled)

            Button {
                FileActions.exportShareCard(app: app, story: story, store: store)
            } label: {
                Label("分享卡片", systemImage: "square.and.arrow.up")
            }

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            StoryMetric(
                title: "首次出现",
                value: firstSeenValue,
                detail: firstSeenDetail
            )
            StoryMetric(
                title: "最后出现",
                value: lastSeenValue,
                detail: lastSeenDetail
            )
            StoryMetric(
                title: "快照出现",
                value: "\(story.appearances) / \(story.totalSnapshots)",
                detail: L.t("包含此应用的快照")
            )
            StoryMetric(
                title: "当前状态",
                value: story.isCurrentlyInstalled ? L.t("已安装") : L.t("已卸载"),
                detail: app.source.title
            )
        }
    }

    private var versionTimeline: some View {
        SectionCard(title: "版本时间线") {
            if story.versions.isEmpty {
                Text("这个应用还没有出现在任何快照中。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(story.versions.enumerated()), id: \.element.id) { index, entry in
                        versionRow(
                            entry,
                            isFirst: index == 0,
                            isLast: index == story.versions.count - 1
                        )
                        if index != story.versions.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func versionRow(
        _ entry: AppStory.VersionEntry,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(entry.version ?? L.t("未知"))
                        .font(.callout.monospacedDigit().weight(.semibold))

                    if let build = entry.build, !build.isEmpty {
                        Text(L.t("构建号 %@", build))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if isFirst {
                        Text("首次记录")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    } else if isLast {
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
            }

            Spacer()

            SourceBadge(source: entry.source, compact: true)

            Text(entry.sizeInBytes?.formatted(.byteCount(style: .file)) ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }

    private var sourceChanges: some View {
        SectionCard(title: "来源变化") {
            VStack(spacing: 0) {
                ForEach(Array(story.sourceChanges.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 10) {
                        SourceBadge(source: entry.source, compact: true)
                        Text(L.t("快照「%@」", entry.snapshotName))
                            .font(.callout)
                        Spacer()
                        Text(entry.capturedAt, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)

                    if index != story.sourceChanges.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var firstSeenValue: String {
        if let snapshot = story.firstSeen {
            return snapshot.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        if let installedAt = app.installedAt {
            return installedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "—"
    }

    private var firstSeenDetail: String {
        if let snapshot = story.firstSeen {
            return L.t("快照「%@」", snapshot.name)
        }
        return L.t("安装时间")
    }

    private var lastSeenValue: String {
        if story.isCurrentlyInstalled {
            return L.t("今天")
        }
        if let snapshot = story.lastSeen {
            return snapshot.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "—"
    }

    private var lastSeenDetail: String {
        if story.isCurrentlyInstalled {
            return L.t("仍在磁盘上")
        }
        if let snapshot = story.lastSeen {
            return L.t("快照「%@」", snapshot.name)
        }
        return L.t("未知")
    }
}

private struct StoryMetric: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
