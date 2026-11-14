import SwiftUI

/// Homebrew 快照列表与详情。
struct BrewSnapshotListView: View {
    @EnvironmentObject private var brew: BrewStore
    var showingComparison: Binding<Bool>
    @State private var selectedID: UUID?
    @State private var kindFilter: BrewPackageKind?

    private var selected: BrewSnapshot? {
        brew.snapshots.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)

            Group {
                if let selected {
                    BrewSnapshotDetailView(snapshot: selected, kindFilter: $kindFilter)
                } else {
                    ContentUnavailableView(
                        L.t("选择一个 Homebrew 快照"),
                        systemImage: "camera",
                        description: Text(L.t("Homebrew 快照记录当时的 Formula 与 Cask，可以导出 Brewfile 或安装脚本。"))
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: brew.snapshots) { _, snapshots in
            if let selectedID, !snapshots.contains(where: { $0.id == selectedID }) {
                self.selectedID = snapshots.first?.id
            } else if selectedID == nil {
                selectedID = snapshots.first?.id
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = brew.snapshots.first?.id }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingComparison.wrappedValue = true
                } label: {
                    Label(L.t("比较 Homebrew 快照"), systemImage: "arrow.left.arrow.right")
                }
                .help(Text(L.t("比较两个 Homebrew 快照的 Formula 与 Cask")))
                .disabled(brew.snapshots.count < 2)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if brew.snapshots.isEmpty {
                ContentUnavailableView(
                    L.t("尚无 Homebrew 快照"),
                    systemImage: "camera",
                    description: Text(L.t("点击工具栏的「保存 Homebrew 快照」，记录当前的 Formula 与 Cask。"))
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(brew.snapshots) { snapshot in
                        BrewSnapshotRow(snapshot: snapshot)
                            .tag(snapshot.id)
                            .contextMenu {
                                Button(L.t("导出 Brewfile…")) {
                                    brew.exportSnapshotBrewfile(snapshot)
                                }
                                Button(L.t("导出安装脚本…")) {
                                    brew.exportSnapshotInstallScript(snapshot)
                                }
                                Divider()
                                Button(L.t("删除快照"), role: .destructive) {
                                    brew.deleteSnapshot(id: snapshot.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct BrewSnapshotRow: View {
    let snapshot: BrewSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(snapshot.name)
                    .lineLimit(1)
                    .fontWeight(.medium)
            }
            HStack(spacing: 5) {
                Text(snapshot.createdAt, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text(L.t("F %d · C %d", snapshot.formulaCount, snapshot.caskCount))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .clipped()
    }
}

private struct BrewSnapshotDetailView: View {
    @EnvironmentObject private var brew: BrewStore
    let snapshot: BrewSnapshot
    @Binding var kindFilter: BrewPackageKind?

    @State private var isEditingName = false
    @State private var nameDraft = ""
    @State private var noteDraft = ""
    @FocusState private var nameFocused: Bool

    private var filtered: [BrewPackage] {
        guard let kindFilter else { return snapshot.packages }
        return snapshot.packages.filter { $0.kind == kindFilter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HStack(spacing: 10) {
                Picker("类型", selection: $kindFilter) {
                    Text("全部").tag(BrewPackageKind?.none)
                    Text("Formula").tag(Optional(BrewPackageKind.formula))
                    Text("Cask").tag(Optional(BrewPackageKind.cask))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)

                Spacer()

                Button(L.t("复制 Brewfile")) {
                    BrewExport.copy(brewfileText)
                }
                .controlSize(.small)

                exportMenu
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.bar)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    L.t("这个快照中没有对应的包"),
                    systemImage: "shippingbox"
                )
            } else {
                BrewSnapshotTable(packages: filtered)
            }
        }
    }

    @ViewBuilder
    private var exportMenu: some View {
        Menu {
            Button(L.t("导出全部 Brewfile…")) {
                brew.exportSnapshotBrewfile(snapshot)
            }
            Button(L.t("只导出 Formula…")) {
                brew.exportSnapshotFormulae(snapshot)
            }
            Button(L.t("只导出 Cask…")) {
                brew.exportSnapshotCasks(snapshot)
            }
            Divider()
            Button(L.t("导出安装脚本…")) {
                brew.exportSnapshotInstallScript(snapshot)
            }
        } label: {
            Label(L.t("导出"), systemImage: "square.and.arrow.up")
        }
        .controlSize(.small)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "camera.fill")
                    .foregroundStyle(.orange)

                if isEditingName {
                    TextField(L.t("快照名称"), text: $nameDraft)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .focused($nameFocused)
                        .onSubmit(commitName)
                } else {
                    Text(snapshot.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .onTapGesture(count: 2) {
                            nameDraft = snapshot.name
                            isEditingName = true
                            nameFocused = true
                        }
                }

                Button {
                    if isEditingName {
                        commitName()
                    } else {
                        nameDraft = snapshot.name
                        isEditingName = true
                        nameFocused = true
                    }
                } label: {
                    Image(systemName: isEditingName ? "checkmark.circle.fill" : "pencil")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text(L.t(isEditingName ? "完成重命名" : "重命名快照")))

                Spacer()

                Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    MetricChip(title: "Formula", value: "\(snapshot.formulaCount)", symbol: "terminal", color: .mint)
                    MetricChip(title: "Cask", value: "\(snapshot.caskCount)", symbol: "shippingbox", color: .orange)
                    MetricChip(title: "可更新", value: "\(snapshot.outdatedCount)", symbol: "arrow.triangle.2.circlepath", color: snapshot.outdatedCount > 0 ? .red : .secondary)
                    MetricChip(title: "已固定", value: "\(snapshot.pinnedCount)", symbol: "pin", color: .blue)
                }
            }

            HStack(spacing: 14) {
                Label(snapshot.hostName, systemImage: "desktopcomputer")
                if let brewVersion = snapshot.brewVersion {
                    Label(L.t("Homebrew %@", brewVersion), systemImage: "mug")
                }
                if let prefix = snapshot.prefix {
                    Label(prefix, systemImage: "folder")
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                TextField(L.t("为这个快照添加备注…"), text: $noteDraft)
                    .textFieldStyle(.plain)
                    .onSubmit(commitNote)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.background)
        .onAppear {
            nameDraft = snapshot.name
            noteDraft = snapshot.note
        }
        .onChange(of: snapshot.id) {
            nameDraft = snapshot.name
            noteDraft = snapshot.note
            isEditingName = false
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused && isEditingName { commitName() }
        }
        .onDisappear { commitNote() }
    }

    private var brewfileText: String {
        BrewfileBuilder.text(
            formulae: snapshot.formulaNames,
            casks: snapshot.caskTokens,
            header: L.t("Custocub Homebrew 快照 · %@", snapshot.name)
        )
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = snapshot.name
            isEditingName = false
            return
        }
        brew.renameSnapshot(id: snapshot.id, name: trimmed)
        isEditingName = false
    }

    private func commitNote() {
        guard noteDraft != snapshot.note else { return }
        brew.updateSnapshotNote(id: snapshot.id, note: noteDraft)
    }
}

private struct BrewSnapshotTable: View {
    let packages: [BrewPackage]

    var body: some View {
        Table(packages) {
            TableColumn("包") { package in
                HStack(spacing: 9) {
                    Image(systemName: package.kind.symbol)
                        .foregroundStyle(package.kind.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(package.title)
                            .lineLimit(1)
                        Text(package.name)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
            }
            .width(min: 220, ideal: 300, max: 400)

            TableColumn("版本") { package in
                Text(package.installedVersionText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 110, max: 160)

            TableColumn("Tap") { package in
                Text(package.tap ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120, max: 170)
        }
    }
}
