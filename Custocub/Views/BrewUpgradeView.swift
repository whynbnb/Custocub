import AppKit
import SwiftUI

/// Homebrew 升级中心：集中查看并升级所有可更新的 Formula 与 Cask。
///
/// 数据来自已安装清单的 `outdated` 字段，执行的是 `brew upgrade`。
struct BrewUpgradeView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var selection: Set<String> = []
    @State private var pendingAction: UpgradeAction?
    @State private var showsTerminal = false

    /// 需要二次确认的升级操作。
    private enum UpgradeAction: Identifiable {
        case all
        case selected([BrewPackage])

        var id: String {
            switch self {
            case .all: "all"
            case .selected(let packages): "selected:" + packages.map(\.id).joined(separator: ",")
            }
        }

        var title: String {
            switch self {
            case .all: L.t("升级全部可更新包？")
            case .selected: L.t("升级所选包？")
            }
        }

        var message: String {
            switch self {
            case .all:
                L.t("将依次升级所有可更新的 Formula 与 Cask。已固定的包会被 Homebrew 跳过。")
            case .selected(let packages):
                L.t("将依次升级 %d 个包。", packages.count)
            }
        }
    }

    private var outdatedPackages: [BrewPackage] {
        brew.packages
            .filter(\.isOutdated)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .formula }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var selectedPackages: [BrewPackage] {
        outdatedPackages.filter { selection.contains($0.id) }
    }

    private var outdatedFormulaCount: Int { outdatedPackages.count { $0.kind == .formula } }
    private var outdatedCaskCount: Int { outdatedPackages.count { $0.kind == .cask } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !brew.isAvailable {
                ContentUnavailableView(
                    L.t("Homebrew 功能当前不可用"),
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text(L.t("开启 Homebrew 功能后才能升级已安装的包。"))
                )
            } else if !brew.hasLoaded && brew.isLoading {
                loadingView
            } else if outdatedPackages.isEmpty {
                emptyView
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Homebrew 升级")
        .task {
            await brew.load()
        }
        .onChange(of: outdatedPackages.map(\.id)) { _, ids in
            // 升级完成后清掉已经不存在的选择。
            selection = selection.intersection(ids)
        }
        .onChange(of: selection) { _, ids in
            // 右侧详情面板跟随当前选中的包。
            if let id = ids.first {
                brew.selectedPackageID = id
            }
        }
        .sheet(isPresented: $showsTerminal) {
            BrewConsoleView()
                .environmentObject(brew)
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingAction {
                Button(L.t("升级")) {
                    perform(action)
                }
            }
            Button(L.t("取消"), role: .cancel) { pendingAction = nil }
        } message: {
            Text(pendingAction?.message ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                Task { await brew.load(force: true) }
            } label: {
                Label(L.t("刷新"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(brew.isLoading || brew.isRunningCommand)

            Button {
                Task { await brew.updateIndex() }
            } label: {
                Label(L.t("检查更新"), systemImage: "arrow.triangle.2.circlepath.circle")
            }
            .controlSize(.small)
            .disabled(brew.isRunningCommand)
            .help(Text(L.t("运行 brew update 后重新读取可升级列表。")))

            Button {
                showsTerminal = true
            } label: {
                Label(L.t("命令日志"), systemImage: "terminal")
            }
            .controlSize(.small)

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                Text(L.t("%d 个可更新", outdatedPackages.count))
                    .foregroundStyle(outdatedPackages.isEmpty ? Color.secondary : Color.red)
                Label("\(outdatedFormulaCount) Formula", systemImage: "terminal")
                    .foregroundStyle(.secondary)
                Label("\(outdatedCaskCount) Cask", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .monospacedDigit()
            .fixedSize()

            if !selectedPackages.isEmpty {
                Button {
                    pendingAction = .selected(selectedPackages)
                } label: {
                    Label(L.t("升级所选 %d 个", selectedPackages.count), systemImage: "arrow.up.circle")
                }
                .controlSize(.small)
                .disabled(brew.isRunningCommand)
            }

            Button {
                pendingAction = .all
            } label: {
                Label(L.t("升级全部"), systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .disabled(brew.isRunningCommand || outdatedPackages.isEmpty)
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .background(.bar)
    }

    // MARK: - Content

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L.t("正在读取 Homebrew 包列表…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(L.t("没有可升级的包"), systemImage: "checkmark.seal")
        } description: {
            Text(L.t("所有已安装的 Formula 与 Cask 都是最新版本。"))
        } actions: {
            Button(L.t("检查更新")) {
                Task { await brew.updateIndex() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(brew.isRunningCommand)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var table: some View {
        Table(outdatedPackages, selection: $selection) {
            TableColumn("包") { package in
                HStack(spacing: 9) {
                    Image(systemName: package.kind.symbol)
                        .foregroundStyle(package.kind.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(package.title)
                                .lineLimit(1)
                            if package.isPinned {
                                UpgradeBadge(text: L.t("已固定"), color: .blue)
                            }
                            if package.isAutoUpdating {
                                UpgradeBadge(text: L.t("自动更新"), color: .secondary)
                            }
                        }
                        Text(package.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .width(min: 220, ideal: 300, max: 420)

            TableColumn("类型") { package in
                Text(package.kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(package.kind.color)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(package.kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
            .width(min: 70, ideal: 82, max: 110)

            TableColumn("已安装") { package in
                Text(package.installedVersionText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 150)

            TableColumn("最新") { package in
                Text(package.latestVersionText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 100, max: 150)

            TableColumn("Tap") { package in
                Text(package.tap ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120, max: 170)

            TableColumn("操作") { package in
                Button(L.t("升级")) {
                    Task { await brew.upgrade([package]) }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(brew.isRunningCommand || package.isPinned)
                .help(package.isPinned
                      ? Text(L.t("已固定的包不会升级，请先取消固定。"))
                      : Text(L.t("升级 %@", package.name)))
            }
            .width(min: 58, ideal: 68, max: 88)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            let packages = outdatedPackages.filter { ids.contains($0.id) && !$0.isPinned }
            guard !packages.isEmpty else { return }
            pendingAction = .selected(packages)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        let selected = outdatedPackages.filter { ids.contains($0.id) }

        if let package = selected.first {
            Button(L.t("升级")) {
                pendingAction = .selected(selected.filter { !$0.isPinned })
            }
            .disabled(selected.allSatisfy(\.isPinned))

            Button(L.t("复制升级命令")) {
                BrewExport.copy(package.upgradeCommand)
            }

            if package.isPinned {
                Button(L.t("取消固定")) {
                    Task { await brew.unpin(package) }
                }
            }

            Divider()

            Button(L.t("在包中查看")) {
                brew.revealPackage(package)
            }

            if let url = package.homepage.flatMap(URL.init(string:)) {
                Button(L.t("打开主页")) {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            Text(L.t("未选择包"))
        }
    }

    private func perform(_ action: UpgradeAction) {
        pendingAction = nil
        switch action {
        case .all:
            Task { await brew.upgradeAll() }
        case .selected(let packages):
            guard !packages.isEmpty else { return }
            selection.removeAll()
            Task { await brew.upgrade(packages) }
        }
    }
}

private struct UpgradeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}
