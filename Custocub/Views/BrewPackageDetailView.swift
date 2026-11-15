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

                dependenciesSection(for: package)

                reverseDependenciesSection(for: package)

                SectionCard(title: "命令") {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                        ForEach(commands(for: package)) { item in
                            GridRow(alignment: .center) {
                                commandButton(item, for: package)

                                Text(item.command)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    BrewExport.copy(item.command)
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

    // MARK: - 依赖关系

    private func dependenciesSection(for package: BrewPackage) -> some View {
        SectionCard(title: "依赖") {
            if package.dependencies.isEmpty {
                emptyRelationLabel(L.t("没有直接依赖"))
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(package.dependencies, id: \.self) { dependency in
                        if let target = brew.package(named: dependency) {
                            packageChip(target)
                        } else {
                            missingDependencyChip(dependency)
                        }
                    }
                }
            }
        }
    }

    private func reverseDependenciesSection(for package: BrewPackage) -> some View {
        let dependents = brew.dependents(of: package)
        return SectionCard(title: "反向依赖") {
            if dependents.isEmpty {
                emptyRelationLabel(L.t("没有其他已安装的包依赖它"))
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(dependents) { dependent in
                        packageChip(dependent)
                    }
                }
            }
        }
    }

    private func emptyRelationLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 可点击的小胶囊：跳到该包的详情。依赖与反向依赖共用。
    private func packageChip(_ target: BrewPackage) -> some View {
        Button {
            brew.focusPackage(target)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: target.kind.symbol)
                    .font(.caption2)
                    .foregroundStyle(target.kind.color)

                Text(target.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(L.t("查看 %@ 详情", target.name)))
    }

    /// 依赖没有对应的已安装包时显示一个只读胶囊。
    private func missingDependencyChip(_ name: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "questionmark.circle")
                .font(.caption2)

            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .foregroundStyle(.secondary)
        .background(Color.secondary.opacity(0.09), in: Capsule())
        .help(Text(L.t("未安装")))
    }

    /// 详情面板里的命令。按钮执行命令，后面的文本方便复制或核对。
    private struct PackageCommand: Identifiable {
        enum Kind: String {
            case install
            case upgrade
            case reinstall
            case uninstall
        }

        let kind: Kind
        let title: String
        let symbol: String
        let command: String

        var id: String { kind.rawValue }

        var isPrimary: Bool { kind == .upgrade }
        var isDestructive: Bool { kind == .uninstall }
    }

    private func commands(for package: BrewPackage) -> [PackageCommand] {
        let upgradePolicy = brew.upgradePolicy
        var items = [
            PackageCommand(
                kind: .install,
                title: L.t("安装"),
                symbol: "arrow.down.circle",
                command: package.installCommand
            )
        ]

        if package.isOutdated {
            items.append(PackageCommand(
                kind: .upgrade,
                title: L.t("升级"),
                symbol: "arrow.up.circle",
                command: package.upgradeCommand(policy: upgradePolicy)
            ))
        }

        items.append(PackageCommand(
            kind: .reinstall,
            title: L.t("重新安装"),
            symbol: "arrow.clockwise",
            command: package.reinstallCommand
        ))
        items.append(PackageCommand(
            kind: .uninstall,
            title: L.t("卸载"),
            symbol: "trash",
            command: package.uninstallCommand
        ))
        return items
    }

    @ViewBuilder
    private func commandButton(_ item: PackageCommand, for package: BrewPackage) -> some View {
        let button = Button(role: item.isDestructive ? .destructive : nil) {
            perform(item, for: package)
        } label: {
            Label(item.title, systemImage: item.symbol)
        }
        .disabled(brew.isRunningCommand)
        .help(item.command)

        if item.isPrimary {
            button.buttonStyle(.borderedProminent)
        } else if item.isDestructive {
            button
                .buttonStyle(.bordered)
                .tint(.red)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private func perform(_ item: PackageCommand, for package: BrewPackage) {
        switch item.kind {
        case .install:
            Task { await brew.install([package.name], kind: package.kind) }
        case .upgrade:
            Task { await brew.upgrade([package]) }
        case .reinstall:
            Task { await brew.reinstall(package) }
        case .uninstall:
            Task { await brew.uninstall([package]) }
        }
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
