import AppKit
import SwiftUI

/// Homebrew 配置与诊断：整合 `brew config` 与 `brew doctor`。
struct BrewHealthView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var showsTerminal = false
    @State private var showsRawConfig = false
    @State private var showsRawDoctor = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !brew.isAvailable {
                ContentUnavailableView(
                    L.t("Homebrew 功能当前不可用"),
                    systemImage: "mug",
                    description: Text(L.t("开启 Homebrew 功能后才能查看配置与诊断。"))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        doctorSection
                        configSection
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Homebrew 配置与诊断")
        .task {
            await brew.loadConfig()
            await brew.runDoctor()
        }
        .sheet(isPresented: $showsTerminal) {
            BrewConsoleView()
                .environmentObject(brew)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if brew.isRunningDoctor || brew.isLoadingConfig {
                ProgressView().controlSize(.small)
                Text(L.t("正在检查…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await brew.runDoctor(force: true) }
            } label: {
                Label(L.t("运行诊断"), systemImage: "stethoscope")
            }
            .controlSize(.small)
            .disabled(brew.isRunningDoctor || brew.isRunningCommand)

            Button {
                Task { await brew.loadConfig(force: true) }
            } label: {
                Label(L.t("重新读取配置"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(brew.isLoadingConfig || brew.isRunningCommand)

            Button {
                showsTerminal = true
            } label: {
                Label(L.t("命令日志"), systemImage: "terminal")
            }
            .controlSize(.small)

            Spacer()

            if let report = brew.doctorReport {
                DoctorStatusBadge(report: report)
            }
        }
        // 固定高度，切换分区时不影响下方布局。
        .frame(height: 40)
        .padding(.horizontal, 16)
        .background(.bar)
    }

    // MARK: - Doctor

    private var doctorSection: some View {
        SectionCard(title: "环境诊断") {
            VStack(alignment: .leading, spacing: 10) {
                if brew.isRunningDoctor && brew.doctorReport == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("正在运行 brew doctor…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if let report = brew.doctorReport {
                    if report.isHealthy {
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title3)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("未发现问题"))
                                    .font(.callout.weight(.medium))
                                Text(L.t("brew doctor 没有报告任何警告或错误。"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        ForEach(report.sortedFindings) { finding in
                            DoctorFindingRow(finding: finding)
                            if finding.id != report.sortedFindings.last?.id {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Text(L.t("检查于 %@", report.checkedAt.formatted(date: .omitted, time: .standard)))
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Button(showsRawDoctor ? L.t("隐藏原始输出") : L.t("原始输出")) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showsRawDoctor.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button(L.t("复制原始输出")) {
                            BrewExport.copy(report.rawText)
                        }
                        .controlSize(.mini)
                    }

                    if showsRawDoctor {
                        RawOutputView(text: report.rawText, maxHeight: 220)
                    }
                } else {
                    Text(L.t("还没有诊断结果。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Config

    private var configSection: some View {
        SectionCard(title: "Homebrew 配置") {
            VStack(alignment: .leading, spacing: 12) {
                if let info = brew.configInfo {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(L.t("筛选配置项"), text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    ForEach(info.presentGroups) { group in
                        let entries = filteredEntries(info.entries(in: group))

                        if !entries.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(LocalizedStringKey(group.title), systemImage: group.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(entries) { entry in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(entry.key)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 170, alignment: .leading)

                                        Text(entry.value)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if group != info.presentGroups.last {
                                Divider()
                            }
                        }
                    }

                    if info.presentGroups.allSatisfy({ filteredEntries(info.entries(in: $0)).isEmpty }) {
                        Text(L.t("没有匹配的配置项"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Button(showsRawConfig ? L.t("隐藏原始输出") : L.t("原始输出")) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showsRawConfig.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button(L.t("复制配置")) {
                            BrewExport.copy(info.rawText)
                        }
                        .controlSize(.mini)
                    }

                    if showsRawConfig {
                        RawOutputView(text: info.rawText, maxHeight: 220)
                    }
                } else if brew.isLoadingConfig {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L.t("正在读取 brew config…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(L.t("无法读取 Homebrew 配置。"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 只在有搜索内容时过滤配置项。
    private func filteredEntries(_ entries: [BrewConfigInfo.Entry]) -> [BrewConfigInfo.Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.key.localizedCaseInsensitiveContains(query)
                || $0.value.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Components

private struct DoctorStatusBadge: View {
    let report: BrewDoctorReport

    private var color: Color {
        if report.isHealthy { return .green }
        return report.errorCount > 0 ? .red : .orange
    }

    private var text: String {
        if report.isHealthy { return L.t("健康") }
        if report.errorCount > 0 { return L.t("%d 个问题", report.findings.count) }
        return L.t("%d 个警告", report.warningCount)
    }

    var body: some View {
        Label(text, systemImage: report.isHealthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

private struct DoctorFindingRow: View {
    let finding: BrewDoctorFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: finding.severity.symbol)
                    .foregroundStyle(color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(finding.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if !finding.affects.isEmpty {
                        FlowChips(items: finding.affects, color: color)
                    }

                    if let remediation = finding.remediationText, !remediation.isEmpty {
                        Text(remediation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(finding.remediationCommands, id: \.self) { command in
                        HStack(spacing: 6) {
                            Text(command)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Button {
                                BrewExport.copy(command)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(Text(L.t("复制命令")))
                        }
                    }

                    ForEach(finding.links, id: \.self) { link in
                        if let url = URL(string: link) {
                            Link(link, destination: url)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(finding.severity.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(color.opacity(0.12), in: Capsule())
                    .fixedSize()
            }
        }
    }

    private var color: Color {
        switch finding.severity {
        case .error: .red
        case .warning: .orange
        case .note: .secondary
        }
    }
}

/// 只读的等宽原始输出。
private struct RawOutputView: View {
    let text: String
    var maxHeight: CGFloat = 200

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: maxHeight)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

/// 一组自适应换行的小标签。
private struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(color.opacity(0.1), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }
}

/// 与清理界面共用的简单自适应布局。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let needed = current == 0 ? size.width : current + spacing + size.width
            if needed > maxWidth, current > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rows.count - 1] = needed
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            }
        }

        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: maxWidth.isFinite ? maxWidth : rows.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
