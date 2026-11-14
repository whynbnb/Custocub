import SwiftUI

/// 标题旁的版本号胶囊。
struct BrewVersionPill: View {
    let version: String

    var body: some View {
        Text(version)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(AppSource.homebrew.color)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(AppSource.homebrew.color.opacity(0.12), in: Capsule())
            .fixedSize()
            .help(Text(L.t("Homebrew %@", version)))
    }
}

/// Homebrew 独立管理界面：包列表、快照与命令。
struct HomebrewView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var showingInstallSheet = false
    @State private var confirmUninstall: [BrewPackage] = []
    @State private var showingUpgradeAllConfirmation = false
    @State private var showingBrewComparison = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            switch brewState {
            case .disabled:
                // 关闭后不显示任何 Homebrew 管理内容。
                disabledView
            case .missing:
                unavailableView
            case .unsupportedVersion:
                unsupportedVersionView
            case .ready:
                Group {
                    switch brew.section {
                    case .packages:
                        packagesSection
                    case .explore:
                        BrewExploreView()
                    case .snapshots:
                        BrewSnapshotListView(showingComparison: $showingBrewComparison)
                    case .services:
                        BrewServicesView()
                    case .cleanup:
                        BrewCleanupView()
                    case .health:
                        BrewHealthView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            Divider()
            if brew.isEnabled {
                BrewConsolePanel()
            }
        }
        .navigationTitle("Homebrew")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingInstallSheet) {
            BrewInstallSheet()
                .environmentObject(brew)
        }
        .sheet(isPresented: $showingBrewComparison) {
            BrewComparisonView()
                .environmentObject(brew)
        }
        .task {
            await brew.load()
        }
        .confirmationDialog(
            L.t("卸载 %d 个包？", confirmUninstall.count),
            isPresented: Binding(
                get: { !confirmUninstall.isEmpty },
                set: { if !$0 { confirmUninstall = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button(L.t("卸载"), role: .destructive) {
                let packages = confirmUninstall
                confirmUninstall = []
                brew.selection.removeAll()
                Task { await brew.uninstall(packages) }
            }
            Button(L.t("取消"), role: .cancel) {
                confirmUninstall = []
            }
        } message: {
            Text(L.t("包文件会被移除。依赖关系由 Homebrew 处理。"))
        }
        .confirmationDialog(
            L.t("升级全部可更新包？"),
            isPresented: $showingUpgradeAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(L.t("升级")) {
                Task { await brew.upgradeAll() }
            }
            Button(L.t("取消"), role: .cancel) {}
        } message: {
            Text(L.t("将依次升级当前可更新的 Formula 与 Cask。"))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Homebrew")
                    .font(.title2.weight(.semibold))

                if brew.detectedVersion != nil {
                    BrewVersionPill(version: brew.brewVersion)
                }

                Image(systemName: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(Text(L.t("在这里集中管理 Formula 和 Cask，并保存独立的 Homebrew 快照。")))
                    .accessibilityLabel("Homebrew 说明")

                Spacer()

                if brew.isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            // 探索分区有自己的目录指标（全部可安装包），
            // 这里就不再重复显示已安装数量，避免两个 Formula 数字互相干扰。
            if brew.section != .explore {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        MetricChip(title: "Formula", value: "\(brew.formulaCount)", symbol: "terminal", color: .mint)
                        MetricChip(title: "Cask", value: "\(brew.caskCount)", symbol: "shippingbox", color: .orange)
                        MetricChip(
                            title: "可更新",
                            value: "\(brew.outdatedCount)",
                            symbol: "arrow.triangle.2.circlepath",
                            color: brew.outdatedCount > 0 ? .red : .secondary
                        )
                        MetricChip(title: "已固定", value: "\(brew.pinnedCount)", symbol: "pin", color: .blue)
                        MetricChip(title: "依赖", value: "\(brew.dependencyCount)", symbol: "link", color: .purple)
                    }
                }
            }

            // 分区切换器固定在左侧，切换时位置不变。
            // 不用固定宽度：中文标签较长时会被裁切，交给 Picker 自己算宽度。
            Picker("视图", selection: $brew.section) {
                ForEach(BrewSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(16)
        .background(.background)
        .opacity(brew.isAvailable ? 1 : 0.55)
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(L.t("未检测到 Homebrew"), systemImage: "mug")
        } description: {
            Text(L.t("安装 Homebrew 后，这里会显示 Formula、Cask、快照和命令日志。"))
        } actions: {
            Link(L.t("打开 Homebrew 官网"), destination: URL(string: "https://brew.sh")!)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            missingHint
        }
    }

    /// 开关开启但本机没有 Homebrew 时的说明。
    private var missingHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(L.t("如果 Homebrew 安装在其他位置，可以重新检测。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L.t("重新检测")) {
                brew.rediscover()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// 已安装但版本低于最低要求时的说明。
    private var unsupportedVersionView: some View {
        ContentUnavailableView {
            Label(L.t("Homebrew 版本过低"), systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 6) {
                Text(L.t("当前版本：%@", brew.detectedVersion?.description ?? L.t("未知")))
                    .font(.callout)
                Text(L.t("Custocub 的 Homebrew 功能需要 %@ 或更高版本。升级 Homebrew 后即可使用。",
                         BrewVersion.minimumSupported.description))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            HStack(spacing: 8) {
                Button(L.t("检查更新并升级")) {
                    Task { await brew.updateIndex() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(brew.isRunningCommand)

                Button(L.t("重新检测版本")) {
                    Task { await brew.refreshVersion() }
                }
                .buttonStyle(.bordered)

                Link(L.t("打开 Homebrew 官网"), destination: URL(string: "https://brew.sh")!)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            unsupportedHint
        }
    }

    private var unsupportedHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(L.t("升级命令：brew update && brew upgrade"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer()

            Button(L.t("复制命令")) {
                BrewExport.copy("brew update && brew upgrade")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// 用户主动关闭 Homebrew 功能时的说明（入口已隐藏，作为过渡状态兜底）。
    private var disabledView: some View {
        ContentUnavailableView {
            Label(L.t("Homebrew 功能已关闭"), systemImage: "mug")
        } description: {
            Text(L.t("开启后可以使用 Formula、Cask、快照和命令日志。应用清单中的 Homebrew 来源不受影响。"))
        } actions: {
            Button(L.t("启用 Homebrew")) {
                brew.isEnabled = true
            }
            .buttonStyle(.borderedProminent)

            SettingsLink {
                Text(L.t("打开设置"))
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 四种界面状态，避免各处重复判断。
    private enum BrewUIState {
        case disabled
        case missing
        case unsupportedVersion
        case ready
    }

    private var brewState: BrewUIState {
        if brew.isDisabledByUser { return .disabled }
        if brew.isMissingInstallation { return .missing }
        if brew.isVersionUnsupported { return .unsupportedVersion }
        return .ready
    }

    // MARK: - Packages

    private var packagesSection: some View {
        VStack(spacing: 0) {
            packageFilterBar
            Divider()

            if brew.hasLoaded && brew.filteredPackages.isEmpty {
                emptyState
            } else {
                BrewPackageTable(
                    packages: brew.filteredPackages,
                    selection: $brew.selection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 空状态需要自己占满剩余空间，否则 VStack 会把头部一起居中，
    /// 导致筛选后顶部出现大片空白。
    private var emptyState: some View {
        ContentUnavailableView(
            L.t("没有符合条件的包"),
            systemImage: "shippingbox",
            description: Text(L.t("请调整搜索内容或筛选条件。"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var packageFilterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(L.t("搜索包名、描述或版本"), text: $brew.searchText)
                .textFieldStyle(.plain)
                .layoutPriority(1)

            if !brew.searchText.isEmpty {
                Button {
                    brew.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text(L.t("清除搜索")))
            }

            Divider().frame(height: 18)

            Picker("类型", selection: $brew.kindFilter) {
                Text("全部类型").tag(BrewPackageKind?.none)
                ForEach(BrewPackageKind.allCases) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .labelsHidden()
            .frame(width: 118)

            Toggle(L.t("可更新"), isOn: $brew.showsOutdatedOnly)
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()

            Toggle(L.t("已固定"), isOn: $brew.showsPinnedOnly)
                .toggleStyle(.button)
                .controlSize(.small)
                .fixedSize()

            Toggle(L.t("依赖"), isOn: $brew.showsDependencyPackages)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(Text(L.t("显示只作为依赖安装的 Formula。取消勾选后只看主动安装的包。")))
                .fixedSize()

            if brew.hasActivePackageFilter {
                Button {
                    brew.resetFilters()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text(L.t("清除筛选")))
            }

            Spacer(minLength: 0)

            if !brew.selection.isEmpty {
                Text(L.t("已选择 %d 个", brew.selection.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()

                Button(L.t("卸载"), role: .destructive) {
                    confirmUninstall = brew.filteredPackages.filter { brew.selection.contains($0.id) }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if brew.section == .packages, brew.isAvailable {
                Button {
                    showingInstallSheet = true
                } label: {
                    Label("安装包", systemImage: "plus")
                }
                .help(Text(L.t("通过 brew install 安装 Formula 或 Cask")))
                .disabled(!brew.isAvailable || brew.isRunningCommand)

                Button {
                    if brew.outdatedCount > 0 {
                        showingUpgradeAllConfirmation = true
                    }
                } label: {
                    Label("升级全部", systemImage: "arrow.triangle.2.circlepath")
                }
                .help(Text(L.t("升级所有可更新的包")))
                .disabled(!brew.isAvailable || brew.isRunningCommand || brew.outdatedCount == 0)

                Menu {
                    Button(L.t("导出全部 Brewfile…")) {
                        brew.exportCurrentBrewfile()
                    }
                    Button(L.t("只导出 Formula…")) {
                        brew.exportCurrentFormulae()
                    }
                    Button(L.t("只导出 Cask…")) {
                        brew.exportCurrentCasks()
                    }
                } label: {
                    Label("导出 Brewfile", systemImage: "square.and.arrow.up")
                }
                .help(Text(L.t("把当前已安装的包导出为 Brewfile")))
                .disabled(!brew.hasLoaded)
            }

            Button {
                Task {
                    if brew.section == .explore {
                        await brew.reloadCatalog()
                    } else {
                        await brew.load(force: true)
                    }
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .help(brew.section == .explore
                  ? Text(L.t("重新下载探索目录与下载量统计"))
                  : Text(L.t("重新读取 Homebrew 包列表")))
            .disabled(brew.isLoading || brew.isLoadingCatalog || brew.isRunningCommand)

            Menu {
                Button(L.t("更新索引")) {
                    Task { await brew.updateIndex() }
                }

                Divider()

                Button(L.t("运行环境诊断")) {
                    Task { await brew.runDoctor(force: true) }
                }
                Button(L.t("查看 Homebrew 配置")) {
                    brew.section = .health
                    Task { await brew.loadConfig(force: true) }
                }
                Button(L.t("查看可更新的包")) {
                    Task { await brew.showOutdated() }
                }
            } label: {
                Label("维护", systemImage: "wrench.and.screwdriver")
            }
            .help(Text(L.t("更新、清理和检查 Homebrew")))
            .disabled(!brew.isAvailable || brew.isRunningCommand)

            Button {
                Task { await brew.saveSnapshot() }
            } label: {
                Label("保存 Homebrew 快照", systemImage: "camera.fill")
            }
            .help(Text(L.t("保存 Formula 与 Cask 的独立快照")))
            .disabled(!brew.isAvailable || brew.isSavingSnapshot || brew.isRunningCommand || !brew.hasLoaded)

            Button {
                NotificationCenter.default.post(name: .custocubShowBrewConsole, object: nil)
            } label: {
                Label("命令日志", systemImage: "terminal")
            }
            .help(Text(L.t("在独立窗口中查看命令日志")))
        }
    }
}

// MARK: - Package table

private struct BrewPackageTable: View {
    @EnvironmentObject private var brew: BrewStore
    let packages: [BrewPackage]
    @Binding var selection: Set<String>

    var body: some View {
        Table(packages, selection: $selection) {
            TableColumn("包") { package in
                HStack(spacing: 9) {
                    Image(systemName: package.kind.symbol)
                        .foregroundStyle(package.kind.color)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(package.title)
                                .lineLimit(1)
                            if package.isDependency {
                                BrewTinyBadge(text: L.t("依赖"), color: .purple)
                            }
                            if package.isPinned {
                                BrewTinyBadge(text: L.t("固定"), color: .blue)
                            }
                            if package.isOutdated {
                                BrewTinyBadge(text: L.t("可更新"), color: .red)
                            }
                            if package.isAutoUpdating {
                                BrewTinyBadge(text: L.t("自动更新"), color: .secondary)
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
            .width(min: 220, ideal: 300, max: 400)

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
                    .foregroundStyle(package.isOutdated ? .primary : .secondary)
            }
            .width(min: 80, ideal: 100, max: 150)

            TableColumn("最新") { package in
                Text(package.latestVersionText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 150)

            TableColumn("Tap") { package in
                Text(package.tap ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120, max: 170)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { ids in
            guard let id = ids.first, let package = brew.package(id: id) else { return }
            brew.copyInstallCommand(package)
        }
        .overlay {
            if brew.isLoading && packages.isEmpty {
                ProgressView(L.t("正在读取 Homebrew 包列表…"))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        let selected = packages.filter { ids.contains($0.id) }

        if let package = selected.first {
            Button(L.t("复制安装命令")) {
                brew.copyInstallCommand(package)
            }
            Button(L.t("复制包名")) {
                BrewExport.copy(package.name)
            }

            Divider()

            if package.isOutdated {
                Button(L.t("升级")) {
                    Task { await brew.upgrade(selected) }
                }
            }

            if package.isPinned {
                Button(L.t("取消固定")) {
                    Task { await brew.unpin(package) }
                }
            } else {
                Button(L.t("固定版本")) {
                    Task { await brew.pin(package) }
                }
            }

            Button(L.t("重新安装")) {
                Task { await brew.reinstall(package) }
            }

            Divider()

            if let url = package.homepage.flatMap(URL.init(string:)) {
                Button(L.t("打开主页")) {
                    NSWorkspace.shared.open(url)
                }
            }

            Button(L.t("卸载"), role: .destructive) {
                Task { await brew.uninstall(selected) }
            }
        } else {
            Text(L.t("未选择包"))
        }
    }
}

private struct BrewTinyBadge: View {
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

// MARK: - Install sheet

private struct BrewInstallSheet: View {
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.dismiss) private var dismiss

    @State private var names = ""
    @State private var kind: BrewPackageKind = .formula

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("安装 Homebrew 包")
                .font(.headline)

            Picker("类型", selection: $kind) {
                ForEach(BrewPackageKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            TextField(L.t("包名，多个用空格分隔"), text: $names)
                .textFieldStyle(.roundedBorder)

            Text(previewCommand)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(L.t("取消")) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(L.t("安装")) {
                    let list = names
                        .split(whereSeparator: { $0.isWhitespace })
                        .map(String.init)
                    dismiss()
                    Task { await brew.install(list, kind: kind) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(names.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var previewCommand: String {
        let list = names.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return BrewPackage.command("install", kind: kind, names: list.isEmpty ? ["<name>"] : list)
    }
}
