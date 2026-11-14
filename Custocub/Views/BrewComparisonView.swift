import SwiftUI

/// 比较两个 Homebrew 快照（Formula + Cask）。
struct BrewComparisonView: View {
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.dismiss) private var dismiss

    @State private var olderID: UUID?
    @State private var newerID: UUID?

    private var older: BrewSnapshot? {
        brew.snapshots.first { $0.id == olderID }
    }

    private var newer: BrewSnapshot? {
        brew.snapshots.first { $0.id == newerID }
    }

    private var changes: [BrewCaskChange] {
        guard let older, let newer else { return [] }
        return BrewComparisonReport.changes(older: older, newer: newer)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Homebrew 快照比较")
                        .font(.title2.weight(.semibold))
                    Text("检查两个时间点之间 Formula 与 Cask 的变化。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.t("复制变更包名")) {
                    BrewExport.copy(changes.map(\.token).joined(separator: "\n"))
                }
                .disabled(changes.isEmpty)

                Button(L.t("完成")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                snapshotPicker(title: "较早快照", selection: $olderID, excluding: newerID)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                snapshotPicker(title: "较晚快照", selection: $newerID, excluding: olderID)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                SummaryMetric(title: "全部变更", value: changes.count, symbol: "list.bullet", color: .primary, selected: false, action: nil)
                SummaryMetric(title: "新增", value: changes.count { $0.kind == .added }, symbol: "plus.circle.fill", color: .green, selected: false, action: nil)
                SummaryMetric(title: "移除", value: changes.count { $0.kind == .removed }, symbol: "minus.circle.fill", color: .red, selected: false, action: nil)
                SummaryMetric(title: "更新", value: changes.count { $0.kind == .updated }, symbol: "arrow.triangle.2.circlepath.circle.fill", color: .orange, selected: false, action: nil)
            }
            .frame(height: 74)

            Divider()

            if older == nil || newer == nil {
                ContentUnavailableView(
                    L.t("请选择两个 Homebrew 快照"),
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text(L.t("至少需要两个 Homebrew 快照才能比较。"))
                )
            } else if changes.isEmpty {
                ContentUnavailableView(
                    L.t("两个快照完全一致"),
                    systemImage: "checkmark.circle",
                    description: Text(L.t("Formula 与 Cask 的版本都没有变化。"))
                )
            } else {
                List(changes) { change in
                    HStack(spacing: 12) {
                        Image(systemName: change.kind.symbol)
                            .foregroundStyle(color(for: change.kind))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(change.displayName)
                                .fontWeight(.medium)
                            Text(change.token)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Group {
                            switch change.kind {
                            case .added:
                                Text(L.t("版本 %@", change.afterVersion ?? L.t("未知")))
                                    .foregroundStyle(.green)
                            case .removed:
                                Text(L.t("版本 %@", change.beforeVersion ?? L.t("未知")))
                                    .foregroundStyle(.red)
                            case .updated:
                                Text(L.t("%@ → %@", change.beforeVersion ?? L.t("未知"), change.afterVersion ?? L.t("未知")))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.callout.monospacedDigit())
                    }
                    .padding(.vertical, 5)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            let sorted = brew.snapshots.sorted { $0.createdAt > $1.createdAt }
            newerID = sorted.first?.id
            olderID = sorted.dropFirst().first?.id
        }
    }

    private func snapshotPicker(title: String, selection: Binding<UUID?>, excluding: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(LocalizedStringKey(title), selection: selection) {
                ForEach(brew.snapshots.filter { $0.id != excluding }) { snapshot in
                    Text("\(snapshot.name) · \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .tag(Optional(snapshot.id))
                }
            }
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for kind: BrewCaskChange.Kind) -> Color {
        switch kind {
        case .added: .green
        case .removed: .red
        case .updated: .orange
        }
    }
}
