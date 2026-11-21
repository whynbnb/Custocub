import AppKit
import SwiftUI

/// 用于导出的应用分享卡片。
struct AppShareCard: View {
    let app: AppRecord
    let story: AppStory

    private var iconImage: NSImage? {
        if let cached = IconProvider.shared.cachedIcon(forPath: app.path) {
            return cached
        }
        if let data = app.iconData {
            return NSImage(data: data)
        }
        guard FileManager.default.fileExists(atPath: app.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: app.path)
    }

    private var historyIcons: [NSImage] {
        Array(
            story.iconHistory
                .reversed()
                .prefix(4)
                .compactMap { NSImage(data: $0.iconData) }
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.09),
                    app.source.color.opacity(0.65)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(app.source.color.opacity(0.22))
                .frame(width: 620, height: 620)
                .blur(radius: 80)
                .offset(x: 360, y: -240)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 28) {
                    iconView
                        .frame(width: 148, height: 148)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .padding(18)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 34))
                        .overlay {
                            RoundedRectangle(cornerRadius: 34)
                                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(app.displayBundleIdentifier)
                            .font(.system(size: 17, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                            .textSelection(.enabled)

                        HStack(spacing: 8) {
                            SourceBadge(source: app.source)
                            PlatformBadge(platform: app.platform)
                            TypeBadge(isSystem: app.isSystemApp)
                        }
                        .padding(.top, 4)
                    }

                    Spacer()
                }

                HStack(spacing: 14) {
                    ShareStat(title: "版本", value: app.displayVersion)
                    ShareStat(title: "大小", value: app.displaySize)
                    ShareStat(title: "首次出现", value: firstSeenText)
                    ShareStat(title: "最后出现", value: lastSeenText)
                    ShareStat(title: "快照出现", value: "\(story.appearances) / \(story.totalSnapshots)")
                }
                .padding(.top, 34)

                if !historyIcons.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("图标历史")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))

                        HStack(spacing: 12) {
                            ForEach(Array(historyIcons.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                        }
                    }
                    .padding(.top, 30)
                }

                Spacer(minLength: 20)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("由 Custocub 生成")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("custos + cubby · 软件收藏与快照")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    Text(app.source.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(52)
        }
        .frame(width: 1200, height: 760)
    }

    @ViewBuilder
    private var iconView: some View {
        if let iconImage {
            Image(nsImage: iconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .scaledToFit()
                .padding(24)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var firstSeenText: String {
        if let snapshot = story.firstSeen {
            return snapshot.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        if let installedAt = app.installedAt {
            return installedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "—"
    }

    private var lastSeenText: String {
        if story.isCurrentlyInstalled {
            return L.t("今天")
        }
        if let snapshot = story.lastSeen {
            return snapshot.createdAt.formatted(date: .abbreviated, time: .omitted)
        }
        return "—"
    }
}

private struct ShareStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(14)
        .frame(minWidth: 170, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
