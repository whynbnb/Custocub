import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ComparisonView: View {
    @EnvironmentObject private var store: CustocubStore
    @Environment(\.dismiss) private var dismiss

    @State private var olderID: UUID?
    @State private var newerID: UUID?
    @State private var kindFilter: AppChange.Kind?
    @State private var sourceFilter: AppSource?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            snapshotSelectors
            Divider()
            summary
            Divider()
            filterBar
            Divider()
            results
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear(perform: configureInitialSelection)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("快照比较")
                    .font(.title2.weight(.semibold))
                Text("检查两个时间点之间应用、来源、架构及元数据的变化。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                exportReport()
            } label: {
                Label("导出报告", systemImage: "square.and.arrow.up")
            }
            .disabled(olderSnapshot == nil || newerSnapshot == nil)

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var snapshotSelectors: some View {
        HStack(spacing: 12) {
            SnapshotPicker(title: "较早快照", selection: $olderID, snapshots: olderOptions)
            Button(action: swapSnapshots) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(.bordered)
            .help("交换比较方向")
            SnapshotPicker(title: "较晚快照", selection: $newerID, snapshots: newerOptions)
        }
        .padding(16)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            SummaryMetric(
                title: "全部变更",
                value: changes.count,
                symbol: "list.bullet",
                color: .primary,
                selected: kindFilter == nil,
                action: { kindFilter = nil }
            )
            ForEach(AppChange.Kind.allCases) { kind in
                SummaryMetric(
                    title: kind.title,
                    value: changes.count { $0.kind == kind },
                    symbol: kind.symbol,
                    color: kind.color,
                    selected: kindFilter == kind,
                    action: { kindFilter = kind }
                )
            }
            SummaryMetric(
                title: "未变化",
                value: unchangedCount,
                symbol: "equal.circle.fill",
                color: .secondary,
                selected: false,
                action: nil
            )
        }
        .frame(height: 74)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索应用、Bundle ID 或变更内容", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除搜索")
            }

            Divider().frame(height: 18)

            Picker("来源", selection: $sourceFilter) {
                Text("全部来源").tag(AppSource?.none)
                ForEach(AppSource.allCases) { source in
                    Label(source.title, systemImage: source.symbol).tag(Optional(source))
                }
            }
            .labelsHidden()
            .frame(width: 145)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder
    private var results: some View {
        if olderSnapshot == nil || newerSnapshot == nil {
            ContentUnavailableView(
                "请选择两个快照",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("至少需要两个快照（可以是历史快照与当前状态）才能进行比较。")
            )
        } else if filteredChanges.isEmpty {
            ContentUnavailableView(
                changes.isEmpty ? "两个快照完全一致" : "没有符合条件的变更",
                systemImage: changes.isEmpty ? "checkmark.circle" : "line.3.horizontal.decrease.circle",
                description: Text(changes.isEmpty
                    ? "应用列表及已记录的元数据均未发生变化。"
                    : "请调整搜索内容或筛选条件。")
            )
        } else {
            List(filteredChanges) { change in
                ChangeRow(change: change)
            }
            .listStyle(.inset)
        }
    }

    private var olderSnapshot: AppSnapshot? {
        store.comparisonSnapshots.first { $0.id == olderID }
    }

    private var newerSnapshot: AppSnapshot? {
        store.comparisonSnapshots.first { $0.id == newerID }
    }

    private var olderOptions: [AppSnapshot] {
        store.comparisonSnapshots.filter { $0.id != newerID }
    }

    private var newerOptions: [AppSnapshot] {
        store.comparisonSnapshots.filter { $0.id != olderID }
    }

    private var changes: [AppChange] {
        guard let olderSnapshot, let newerSnapshot else { return [] }
        return AppChange.compare(olderSnapshot, newerSnapshot)
    }

    private var unchangedCount: Int {
        guard let olderSnapshot else { return 0 }
        let removed = changes.count { $0.kind == .removed }
        let updated = changes.count { $0.kind == .updated }
        return max(0, olderSnapshot.apps.count - removed - updated)
    }

    private var filteredChanges: [AppChange] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return changes.filter { change in
            let matchesKind = kindFilter == nil || change.kind == kindFilter
            let matchesSource = sourceFilter == nil || change.app.source == sourceFilter
            let searchable = [
                change.app.name,
                change.app.bundleIdentifier ?? "",
                change.app.path,
                change.app.source.title,
                change.fieldChanges.flatMap { [$0.field.title, $0.oldValue, $0.newValue] }.joined(separator: " ")
            ].joined(separator: " ")
            let matchesSearch = query.isEmpty || searchable.localizedCaseInsensitiveContains(query)
            return matchesKind && matchesSource && matchesSearch
        }
    }

    private func configureInitialSelection() {
        let available = store.comparisonSnapshots.sorted { $0.createdAt > $1.createdAt }
        guard available.count >= 2 else { return }

        newerID = available[0].id
        olderID = available[1].id
    }

    private func swapSnapshots() {
        (olderID, newerID) = (newerID, olderID)
    }

    private func exportReport() {
        guard let olderSnapshot, let newerSnapshot else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Custocub-\(olderSnapshot.name)-\(newerSnapshot.name)-对比.md"
        panel.message = "导出当前快照对比报告"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try ComparisonReport.markdown(
                    older: olderSnapshot,
                    newer: newerSnapshot,
                    changes: changes
                ).write(to: url, atomically: true, encoding: .utf8)
            } catch {
                store.errorMessage = "无法导出对比报告：\(error.localizedDescription)"
            }
        }
    }
}

private struct SnapshotPicker: View {
    @EnvironmentObject private var store: CustocubStore
    let title: String
    @Binding var selection: UUID?
    let snapshots: [AppSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(snapshots) { snapshot in
                    Text("\(snapshot.name) · \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .tag(Optional(snapshot.id))
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: Int
    let symbol: String
    let color: Color
    let selected: Bool
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value, format: .number)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? color.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .overlay(alignment: .trailing) { Divider() }
    }
}

private struct ChangeRow: View {
    let change: AppChange

    var body: some View {
        DisclosureGroup {
            changeDetails
                .padding(.leading, 74)
                .padding(.vertical, 8)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: change.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(change.kind.color)
                    .frame(width: 22)

                AppIconView(app: change.app, size: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(change.app.name)
                        .fontWeight(.medium)
                    Text(change.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                PlatformBadge(platform: change.app.platform)
                SourceBadge(source: change.app.source, compact: true)
            }
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var changeDetails: some View {
        switch change.kind {
        case .added:
            MetadataDetails(app: change.app, label: "新增应用")
        case .removed:
            MetadataDetails(app: change.app, label: "移除前信息")
        case .updated:
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("字段").foregroundStyle(.secondary)
                    Text("之前").foregroundStyle(.secondary)
                    Text("之后").foregroundStyle(.secondary)
                }
                ForEach(change.fieldChanges) { field in
                    GridRow {
                        Text(field.field.title)
                            .fontWeight(.medium)
                        Text(field.oldValue)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                            Text(field.newValue)
                        }
                    }
                }
            }
            .textSelection(.enabled)
        }
    }
}

private struct MetadataDetails: View {
    let app: AppRecord
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SourceBadge(source: app.source)
                PlatformBadge(platform: app.platform)
                TypeBadge(isSystem: app.isSystemApp)
                if app.isOwn {
                    OwnAppBadge()
                }
            }
            Text("版本：\(app.displayVersion)\(app.build.map { " (\($0))" } ?? "")")
            Text("Bundle ID：\(app.displayBundleIdentifier)")
            if let steamAppID = app.steamAppID {
                Text("Steam App ID：\(steamAppID)")
            }
            Text("大小：\(app.displaySize)")
            Text("位置：\(app.path)")
            Text("安装：\(app.installedAtText)　更新：\(app.updatedAtText)")
        }
        .font(.callout)
        .textSelection(.enabled)
    }
}

extension AppChange.Kind {
    var color: Color {
        switch self {
        case .added: .green
        case .removed: .red
        case .updated: .orange
        }
    }
}
