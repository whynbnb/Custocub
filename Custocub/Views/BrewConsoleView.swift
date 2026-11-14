import SwiftUI

/// 让主界面可以打开独立的命令日志窗口。
extension Notification.Name {
    static let custocubShowBrewConsole = Notification.Name("custocub.showBrewConsole")
}

/// 内嵌在 Homebrew 界面底部的命令日志面板。
struct BrewConsolePanel: View {
    @EnvironmentObject private var brew: BrewStore
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()
                BrewConsoleLogList(maxHeight: 180)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: brew.isRunningCommand) { _, isRunning in
            if isRunning {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded = true
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)
                    Text(L.t("命令日志"))
                        .font(.caption.weight(.medium))
                    if !brew.logEntries.isEmpty {
                        Text("\(brew.logEntries.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if brew.isRunningCommand {
                ProgressView().controlSize(.mini)
                Text(L.t("正在执行…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if brew.isRunningCommand {
                Button(L.t("停止")) {
                    brew.cancelRunningCommand()
                }
                .controlSize(.mini)
            }

            Button {
                NotificationCenter.default.post(name: .custocubShowBrewConsole, object: nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Text(L.t("在独立窗口中查看命令日志")))

            Button(L.t("清空")) {
                brew.clearLog()
            }
            .controlSize(.mini)
            .disabled(brew.logEntries.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }
}

/// 只显示日志正文的滚动列表，供内嵌面板和弹窗共用。
struct BrewConsoleLogList: View {
    @EnvironmentObject private var brew: BrewStore
    var maxHeight: CGFloat?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(brew.logEntries) { entry in
                        BrewLogRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: maxHeight)
            .onChange(of: brew.logEntries.count) {
                guard let last = brew.logEntries.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .overlay {
                if brew.logEntries.isEmpty {
                    Text(L.t("安装、升级或卸载包时，这里会显示命令和实时输出。"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// 独立的命令日志窗口：日志 + 历史记录。
struct BrewConsoleView: View {
    @EnvironmentObject private var brew: BrewStore
    @Environment(\.dismiss) private var dismiss

    @State private var showsHistory = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                BrewConsoleLogList()
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)

                if showsHistory {
                    historyList
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .navigationTitle("Homebrew 命令")
    }

    private var header: some View {
        HStack(spacing: 10) {
            if brew.isRunningCommand {
                ProgressView().controlSize(.small)
                Text(L.t("正在执行 Homebrew 命令…"))
                    .font(.callout)
            } else {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text(L.t("命令日志"))
                    .font(.callout)
            }

            Spacer()

            if brew.isRunningCommand {
                Button(L.t("停止"), role: .destructive) {
                    brew.cancelRunningCommand()
                }
                .controlSize(.small)
            }

            Toggle(L.t("历史记录"), isOn: $showsHistory)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Button(L.t("清空日志")) {
                brew.clearLog()
            }
            .controlSize(.small)
            .disabled(brew.logEntries.isEmpty)

            Button(L.t("关闭")) { dismiss() }
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.t("最近命令"))
                    .font(.callout.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider()

            if brew.history.isEmpty {
                Text(L.t("暂无历史命令"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(brew.history) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: item.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(item.succeeded ? .green : .red)
                            Text(item.title)
                                .lineLimit(1)
                        }
                        Text(item.commandLine)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 5) {
                            Text(item.date, format: .dateTime.hour().minute().second())
                            Text("·")
                            Text(L.t("%.1f 秒", item.duration))
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button(L.t("重新执行")) {
                            brew.rerun(item)
                        }
                        Button(L.t("复制命令")) {
                            BrewExport.copy(item.commandLine)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct BrewLogRow: View {
    let entry: BrewLogEntry

    var body: some View {
        Group {
            switch entry.level {
            case .command:
                Text(entry.text)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)
            case .info:
                Text(entry.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            case .success:
                Label(entry.text, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            case .failure:
                Label(entry.text, systemImage: "xmark.octagon.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            case .output:
                Text(entry.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
