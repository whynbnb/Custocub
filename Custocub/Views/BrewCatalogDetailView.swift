import AppKit
import SwiftUI

/// 探索列表中选中包的详情面板。
///
/// 数据来自完整目录（可能尚未安装），因此操作以「安装 / 复制命令」为主；
/// 已安装时额外给出跳转到「包」分区的入口。
struct BrewCatalogDetailView: View {
    @EnvironmentObject private var brew: BrewStore
    let entry: BrewCatalogEntry?
    let ranking: BrewPopularityRanking?

    var body: some View {
        Group {
            if let entry {
                detail(for: entry)
            } else {
                ContentUnavailableView(
                    L.t("选择一个包"),
                    systemImage: "safari",
                    description: Text(L.t("这里列出 Homebrew 仓库中的全部 Formula 与 Cask，选中后可查看描述与安装方式。"))
                )
            }
        }
        .navigationTitle("Homebrew 探索详情")
    }

    private func detail(for entry: BrewCatalogEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(entry)

                HStack(spacing: 8) {
                    if brew.isInstalled(entry) {
                        Button {
                            brew.revealInstalled(entry)
                        } label: {
                            Label(L.t("在已安装中查看"), systemImage: "shippingbox")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            Task { await brew.install(entry) }
                        } label: {
                            Label(L.t("安装"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        brew.copyInstallCommand(entry)
                    } label: {
                        Label(L.t("复制命令"), systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .help(Text(L.t("复制安装命令")))

                    if let url = entry.homepage.flatMap(URL.init(string:)) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label(L.t("打开主页"), systemImage: "safari")
                                .labelStyle(.iconOnly)
                        }
                        .help(Text(L.t("打开主页")))
                    }

                    Spacer()
                }
                .controlSize(.small)
                .disabled(brew.isRunningCommand)

                SectionCard(title: "基本信息") {
                    DetailRow(label: "包名", value: entry.name, monospaced: true)
                    DetailRow(label: "类型", value: entry.kind.title)
                    DetailRow(label: "最新版本", value: entry.latestVersion ?? L.t("未知"))
                    DetailRow(label: "Tap", value: entry.tapText, monospaced: true)
                    if let license = entry.license, !license.isEmpty {
                        DetailRow(label: "许可证", value: license)
                    }
                    if let installed = brew.installedVersion(for: entry) {
                        DetailRow(label: "已安装版本", value: installed)
                    }
                }

                if let summary = entry.summary, !summary.isEmpty {
                    SectionCard(title: "说明") {
                        Text(summary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !entry.aliases.isEmpty {
                    SectionCard(title: "别名") {
                        Text(entry.aliases.joined(separator: " · "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SectionCard(title: "下载量") {
                    if let ranking {
                        DetailRow(label: "统计范围", value: ranking.dateRangeText ?? brew.exploreRange.title)
                        DetailRow(label: "下载量", value: ranking.countText(for: entry))
                        DetailRow(label: "占比", value: ranking.percentText(for: entry))
                        if let rank = ranking.rank(for: entry) {
                            DetailRow(label: "排名", value: "#\(rank)")
                        }
                    } else {
                        Text(L.t("暂无下载量数据。"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                SectionCard(title: "命令") {
                    ForEach([entry.installCommand, entry.infoCommand, entry.uninstallCommand], id: \.self) { line in
                        HStack(spacing: 8) {
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                BrewExport.copy(line)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(Text(L.t("复制")))
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func header(_ entry: BrewCatalogEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.kind.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(entry.kind.color)
                .frame(width: 76, height: 76)
                .background(entry.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 7) {
                Text(entry.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    BrewStateBadge(text: entry.kind.title, color: entry.kind.color)
                    if entry.isDeprecated {
                        BrewStateBadge(text: L.t("已弃用"), color: .orange)
                    }
                    if entry.isDisabled {
                        BrewStateBadge(text: L.t("已停用"), color: .red)
                    }
                    if brew.isInstalled(entry) {
                        BrewStateBadge(text: L.t("已安装"), color: .green)
                    }
                    Spacer(minLength: 0)
                }

                Text(entry.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}
