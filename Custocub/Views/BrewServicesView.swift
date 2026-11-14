import AppKit
import SwiftUI

/// `brew services` 管理界面：查看和控制后台服务。
struct BrewServicesView: View {
    @EnvironmentObject private var brew: BrewStore

    @State private var selection: String?
    @State private var confirmAction: ServiceAction?
    @State private var showsTerminal = false

    /// 需要二次确认的操作。
    enum ServiceAction: Identifiable {
        case stop(BrewServiceInfo)
        case kill(BrewServiceInfo)
        case stopAll
        case cleanup

        var id: String {
            switch self {
            case .stop(let service): "stop:\(service.id)"
            case .kill(let service): "kill:\(service.id)"
            case .stopAll: "stopAll"
            case .cleanup: "cleanup"
            }
        }

        var title: String {
            switch self {
            case .stop(let service): L.t("停止服务 %@？", service.name)
            case .kill(let service): L.t("立即停止服务 %@？", service.name)
            case .stopAll: L.t("停止全部服务？")
            case .cleanup: L.t("清理无用服务？")
            }
        }

        var message: String {
            switch self {
            case .stop(let service):
                L.t("会停止「%@」并取消登录时自动启动。可以随时重新启动。", service.name)
            case .kill(let service):
                L.t("会立即停止「%@」，但保留登录时自动启动的注册。", service.name)
            case .stopAll:
                L.t("会停止所有已注册的服务，并取消它们的自动启动注册。")
            case .cleanup:
                L.t("会移除已失效、未被任何服务使用的服务文件，不会停止正在运行的服务。")
            }
        }

        var isDestructive: Bool {
            switch self {
            case .stop, .kill, .stopAll: true
            case .cleanup: false
            }
        }
    }

    private var services: [BrewServiceInfo] { brew.serviceEntries }

    private var runningCount: Int {
        services.count { $0.status == .started || $0.status == .scheduled }
    }

    private var registeredCount: Int {
        services.count { $0.registered }
    }

    private var errorCount: Int {
        services.count { $0.status == .error }
    }

    private var selectedService: BrewServiceInfo? {
        guard let selection else { return nil }
        return services.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if !brew.isAvailable {
                ContentUnavailableView(
                    L.t("Homebrew 功能当前不可用"),
                    systemImage: "mug",
                    description: Text(L.t("开启 Homebrew 功能后才能管理后台服务。"))
                )
            } else if services.isEmpty && brew.isLoadingServices {
                loadingView
            } else if services.isEmpty {
                emptyView
            } else {
                // HSplitView 不会自动铺满剩余高度，用 GeometryReader 明确撑满。
                GeometryReader { geometry in
                    HSplitView {
                        serviceList
                            .frame(minWidth: 320, idealWidth: 420, maxWidth: 560, maxHeight: .infinity)
                        serviceDetail
                            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Homebrew 服务")
        .task {
            await brew.loadServices()
        }
        .sheet(isPresented: $showsTerminal) {
            BrewConsoleView()
                .environmentObject(brew)
        }
        .confirmationDialog(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = confirmAction {
                Button(L.t("继续"), role: action.isDestructive ? .destructive : nil) {
                    let target = action
                    confirmAction = nil
                    Task { await perform(target) }
                }
            }
            Button(L.t("取消"), role: .cancel) { confirmAction = nil }
        } message: {
            Text(confirmAction?.message ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if brew.isLoadingServices {
                ProgressView().controlSize(.small)
                Text(L.t("正在读取…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await brew.loadServices(force: true) }
            } label: {
                Label(L.t("刷新"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(brew.isLoadingServices || brew.isRunningCommand)

            Button {
                Task { await brew.startAllServices() }
            } label: {
                Label(L.t("启动全部"), systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(brew.isRunningCommand || registeredCount == 0)

            Button {
                confirmAction = .stopAll
            } label: {
                Label(L.t("停止全部"), systemImage: "stop.fill")
            }
            .controlSize(.small)
            .disabled(brew.isRunningCommand || registeredCount == 0)

            Button {
                Task { await brew.cleanupServices() }
            } label: {
                Label(L.t("清理无用服务"), systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(brew.isRunningCommand)

            Button {
                showsTerminal = true
            } label: {
                Label(L.t("命令日志"), systemImage: "terminal")
            }
            .controlSize(.small)

            Spacer()

            serviceMetrics
        }
        .frame(height: 40)
        .padding(.horizontal, 16)
        .background(.bar)
    }

    private var serviceMetrics: some View {
        HStack(spacing: 10) {
            Label(L.t("%d 运行中", runningCount), systemImage: "bolt.fill")
                .foregroundStyle(runningCount > 0 ? .green : .secondary)
            Label(L.t("%d 已注册", registeredCount), systemImage: "checkmark.seal")
                .foregroundStyle(.secondary)
            if errorCount > 0 {
                Label(L.t("%d 出错", errorCount), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .fixedSize()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L.t("正在读取 brew services…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(L.t("没有可管理的服务"), systemImage: "gearshape.2")
        } description: {
            Text(L.t("只有带有 service 定义的 Formula 才会出现在这里，例如 postgresql、redis、nginx 等。"))
        } actions: {
            Button(L.t("重新读取")) {
                Task { await brew.loadServices(force: true) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var serviceList: some View {
        List(services, selection: $selection) { service in
            ServiceRow(service: service)
                .tag(service.id)
                .contextMenu {
                    contextMenu(for: service)
                }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            listFooter
        }
    }

    private var listFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text(L.t("「运行中」表示进程在跑；「已注册」表示登录时会自动启动。"))
                .font(.caption2)
                .lineLimit(1)
            Spacer()
            if let lastLoaded = brew.lastServicesLoadedAt {
                Text(lastLoaded, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func contextMenu(for service: BrewServiceInfo) -> some View {
        if service.canStart {
            Button(L.t("启动")) {
                Task { await brew.startService(service) }
            }
            Button(L.t("运行一次（不自动启动）")) {
                Task { await brew.runServiceOnce(service) }
            }
        }

        if service.canStop {
            Button(L.t("重启")) {
                Task { await brew.restartService(service) }
            }
            Button(L.t("立即停止（保留自动启动）")) {
                confirmAction = .kill(service)
            }
            Button(L.t("停止并取消自动启动"), role: .destructive) {
                confirmAction = .stop(service)
            }
        }

        Divider()

        if let logPath = service.logPath {
            Button(L.t("打开日志")) {
                openIfExists(logPath)
            }
        }
        if let file = service.loadedFile ?? service.file {
            Button(L.t("在访达中显示服务文件")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)])
            }
        }
        Button(L.t("复制服务名")) {
            BrewExport.copy(service.name)
        }
    }

    // MARK: - Detail

    private var serviceDetail: some View {
        Group {
            if let service = selectedService {
                ServiceDetailView(service: service) { action in
                    confirmAction = action
                }
            } else {
                ContentUnavailableView(
                    L.t("选择一个服务"),
                    systemImage: "gearshape.2",
                    description: Text(L.t("从左侧选择服务，查看命令、PID、日志路径与运行状态。"))
                )
            }
        }
    }

    // MARK: - Actions

    private func perform(_ action: ServiceAction) async {
        switch action {
        case .stop(let service):
            await brew.stopService(service)
        case .kill(let service):
            await brew.killService(service)
        case .stopAll:
            await brew.stopAllServices()
        case .cleanup:
            await brew.cleanupServices()
        }
    }

    private func openIfExists(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

// MARK: - List row

private struct ServiceRow: View {
    let service: BrewServiceInfo

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if service.schedulable {
                        Text(L.t("定时"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                }

                if !service.subtitle.isEmpty {
                    Text(service.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let command = service.command {
                    Text(command)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            ServiceStatusBadge(status: service.status)
        }
        .padding(.vertical, 3)
    }

    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch service.status {
        case .started: .green
        case .scheduled: .purple
        case .error: .red
        case .stopped: .orange
        default: .secondary
        }
    }
}

private struct ServiceStatusBadge: View {
    let status: BrewServiceInfo.Status

    private var color: Color {
        switch status {
        case .started: .green
        case .scheduled: .purple
        case .error: .red
        case .stopped: .orange
        case .none: .secondary
        case .unknown, .other: .yellow
        }
    }

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

// MARK: - Detail

private struct ServiceDetailView: View {
    @EnvironmentObject private var brew: BrewStore
    let service: BrewServiceInfo
    let requestAction: (BrewServicesView.ServiceAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                HStack(spacing: 8) {
                    if service.canStart {
                        Button {
                            Task { await brew.startService(service) }
                        } label: {
                            Label(L.t("启动"), systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await brew.runServiceOnce(service) }
                        } label: {
                            Label(L.t("运行一次"), systemImage: "play.circle")
                        }
                    }

                    if service.canStop {
                        Button {
                            Task { await brew.restartService(service) }
                        } label: {
                            Label(L.t("重启"), systemImage: "arrow.clockwise")
                        }

                        Button {
                            requestAction(.stop(service))
                        } label: {
                            Label(L.t("停止"), systemImage: "stop.fill")
                        }
                    }

                    Spacer()
                }
                .controlSize(.small)
                .disabled(brew.isRunningCommand)

                SectionCard(title: "状态") {
                    DetailRow(label: "运行状态", value: service.status.title)
                    DetailRow(label: "已注册", value: service.registered ? L.t("是") : L.t("否"))
                    if let pid = service.pid {
                        DetailRow(label: "PID", value: "\(pid)", monospaced: true)
                    }
                    if let exitCode = service.exitCode {
                        DetailRow(label: "退出码", value: "\(exitCode)", monospaced: true)
                    }
                    if let user = service.user {
                        DetailRow(label: "运行用户", value: user)
                    }
                    DetailRow(label: "服务名", value: service.serviceName ?? service.name, monospaced: true)
                    if service.schedulable {
                        DetailRow(label: "调度", value: service.cron ?? service.interval ?? L.t("已启用"))
                    }
                }

                if let command = service.command, !command.isEmpty {
                    SectionCard(title: "启动命令") {
                        HStack(spacing: 8) {
                            Text(command)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

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
                }

                SectionCard(title: "文件与日志") {
                    if let file = service.loadedFile ?? service.file {
                        DetailRow(label: "服务文件", value: file, monospaced: true)
                    }
                    if let workingDir = service.workingDir {
                        DetailRow(label: "工作目录", value: workingDir, monospaced: true)
                    }
                    if let logPath = service.logPath {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(L.t("日志"))
                                .foregroundStyle(.secondary)
                                .frame(width: 108, alignment: .leading)
                            Text(logPath)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Button(L.t("打开")) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                            }
                            .controlSize(.mini)
                        }
                    }
                    if let errorLog = service.errorLogPath, errorLog != service.logPath {
                        DetailRow(label: "错误日志", value: errorLog, monospaced: true)
                    }
                }

                SectionCard(title: "更多操作") {
                    HStack(spacing: 8) {
                        if service.canStop {
                            Button(L.t("立即停止")) {
                                requestAction(.kill(service))
                            }
                        }
                        if service.registered {
                            Button(L.t("停止但保留自动启动")) {
                                Task { await brew.stopServiceKeepingRegistration(service) }
                            }
                        }
                        Button(L.t("复制服务名")) {
                            BrewExport.copy(service.name)
                        }
                        Spacer()
                    }
                    .controlSize(.small)
                    .disabled(brew.isRunningCommand)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gearshape.2.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(statusColor)
                .frame(width: 60, height: 60)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text(service.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    ServiceStatusBadge(status: service.status)
                    if service.registered {
                        Text(L.t("自动启动"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                    if service.schedulable {
                        Text(L.t("定时任务"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }

                Text(service.serviceName ?? service.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch service.status {
        case .started: .green
        case .scheduled: .purple
        case .error: .red
        case .stopped: .orange
        default: .secondary
        }
    }
}
