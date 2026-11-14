import SwiftUI

/// Homebrew 包的详情面板。
struct BrewPackageDetailView: View {
    @EnvironmentObject private var brew: BrewStore
    let package: BrewPackage?

    var body: some View {
        Group {
            if let package {
                detail(for: package)
            } else {
                ContentUnavailableView(
                    L.t("选择一个 Homebrew 包"),
                    systemImage: "shippingbox",
                    description: Text(L.t("从列表中选择 Formula 或 Cask，查看版本、依赖和可用命令。"))
                )
            }
        }
        .navigationTitle("Homebrew 包详情")
    }

    private func detail(for package: BrewPackage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(package)

                HStack(spacing: 8) {
                    if package.isOutdated {
                        Button {
                            Task { await brew.upgrade([package]) }
                        } label: {
                            Label(L.t("升级"), systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        Task { await brew.reinstall(package) }
                    } label: {
                        Label(L.t("重新安装"), systemImage: "arrow.clockwise")
                    }

                    Button {
                        brew.copyInstallCommand(package)
                    } label: {
                        Label(L.t("复制命令"), systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .help(Text(L.t("复制安装命令")))

                    if let url = package.homepage.flatMap(URL.init(string:)) {
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
                    DetailRow(label: "包名", value: package.name, monospaced: true)
                    DetailRow(label: "类型", value: package.kind.title)
                    DetailRow(label: "已安装版本", value: package.installedVersionText)
                    DetailRow(label: "最新版本", value: package.latestVersionText)
                    DetailRow(label: "Tap", value: package.tap ?? L.t("未知"), monospaced: true)
                    DetailRow(label: "安装时间", value: package.installedAtText)
                }

                if let summary = package.summary, !summary.isEmpty {
                    SectionCard(title: "说明") {
                        Text(summary)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SectionCard(title: "状态") {
                    HStack(spacing: 8) {
                        BrewStateBadge(
                            text: package.isOutdated ? L.t("可更新") : L.t("已是最新"),
                            color: package.isOutdated ? .red : .green
                        )
                        if package.isPinned {
                            BrewStateBadge(text: L.t("已固定"), color: .blue)
                        }
                        if package.isDependency {
                            BrewStateBadge(text: L.t("作为依赖安装"), color: .purple)
                        }
                        if package.isAutoUpdating {
                            BrewStateBadge(text: L.t("自动更新"), color: .secondary)
                        }
                        Spacer()
                    }
                }

                if !package.dependencies.isEmpty {
                    SectionCard(title: "运行时依赖") {
                        ForEach(package.dependencies, id: \.self) { dependency in
                            Text(dependency)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                SectionCard(title: "命令") {
                    ForEach(commandLines(package), id: \.self) { line in
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

                SectionCard(title: "操作") {
                    HStack(spacing: 8) {
                        if package.isPinned {
                            Button(L.t("取消固定")) {
                                Task { await brew.unpin(package) }
                            }
                        } else {
                            Button(L.t("固定版本")) {
                                Task { await brew.pin(package) }
                            }
                        }

                        if let url = package.homepage.flatMap(URL.init(string:)) {
                            Button(L.t("打开主页")) {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        Spacer()

                        Button(L.t("卸载"), role: .destructive) {
                            Task { await brew.uninstall([package]) }
                        }
                    }
                    .controlSize(.small)
                    .disabled(brew.isRunningCommand)
                }
            }
            .padding(18)
        }
    }

    private func header(_ package: BrewPackage) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: package.kind.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(package.kind.color)
                .frame(width: 76, height: 76)
                .background(package.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 7) {
                Text(package.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    BrewStateBadge(text: package.kind.title, color: package.kind.color)
                    if package.isOutdated {
                        BrewStateBadge(text: L.t("可更新"), color: .red)
                    }
                    if package.isPinned {
                        BrewStateBadge(text: L.t("固定"), color: .blue)
                    }
                    if package.isDependency {
                        BrewStateBadge(text: L.t("依赖"), color: .purple)
                    }
                    Spacer(minLength: 0)
                }

                Text(package.name)
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

    private func commandLines(_ package: BrewPackage) -> [String] {
        var lines = [package.installCommand, package.reinstallCommand, package.uninstallCommand]
        if package.isOutdated {
            lines.insert(package.upgradeCommand, at: 1)
        }
        return lines
    }
}

struct BrewStateBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .fixedSize()
    }
}
