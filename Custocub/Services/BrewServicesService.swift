import Foundation

/// 一个可被 `brew services` 管理的后台服务。
///
/// 对应 `brew services info --all --json` 的字段：
/// - `status`：`started` / `stopped` / `scheduled` / `none` / `error` / `unknown` / `other`
/// - `running`：当前是否有 PID
/// - `registered`：是否已注册为登录（或开机）启动
/// - `schedulable`：是否为定时任务（`interval` / `cron`）
struct BrewServiceInfo: Identifiable, Codable, Hashable, Sendable {
    var name: String
    var serviceName: String?
    var status: Status
    var running: Bool
    var loaded: Bool
    var schedulable: Bool
    var registered: Bool
    var pid: Int?
    var exitCode: Int?
    var user: String?
    var file: String?
    var loadedFile: String?
    var command: String?
    var workingDir: String?
    var rootDir: String?
    var logPath: String?
    var errorLogPath: String?
    var interval: String?
    var cron: String?

    var id: String { name }

    enum Status: String, Codable, CaseIterable, Sendable {
        case started
        case stopped
        case scheduled
        case none
        case error
        case unknown
        case other

        var title: String {
            switch self {
            case .started: L.t("运行中")
            case .stopped: L.t("已停止")
            case .scheduled: L.t("已计划")
            case .none: L.t("未注册")
            case .error: L.t("出错")
            case .unknown: L.t("未知")
            case .other: L.t("其他")
            }
        }

        /// 是否需要在界面上突出显示（正在跑或有问题）。
        var isActive: Bool {
            self == .started || self == .scheduled
        }
    }

    /// 是否有可管理的服务文件。`none` 但存在源文件时也可以启动。
    var canStart: Bool {
        status == .stopped || status == .none || status == .error
    }

    var canStop: Bool {
        registered || running
    }

    /// 用于排序：运行中优先，其次已注册，最后未注册。
    var sortWeight: Int {
        switch status {
        case .started: 0
        case .scheduled: 1
        case .error: 2
        case .stopped: 3
        case .none: 4
        case .unknown, .other: 5
        }
    }

    var subtitle: String {
        var parts: [String] = []
        if let user, !user.isEmpty { parts.append(user) }
        if let pid { parts.append("PID \(pid)") }
        if status == .error, let exitCode { parts.append(L.t("退出码 %d", exitCode)) }
        return parts.joined(separator: " · ")
    }
}

/// 读取与管理 `brew services` 的服务层。
enum BrewServicesService {
    /// 读取全部可管理服务的完整信息。这个命令很快（约 0.5 秒）。
    static func load() async -> [BrewServiceInfo]? {
        guard BrewService.isAvailable else { return nil }

        let result = await BrewService.runQuiet(arguments: ["services", "info", "--all", "--json"])
        guard result.result.exitCode == 0 || !result.output.isEmpty else { return nil }

        return parse(result.output)
    }

    /// 解析 `brew services info --all --json`。
    static func parse(_ output: String) -> [BrewServiceInfo]? {
        // 输出前可能有提示行，从第一个 `[` 开始截取。
        guard let start = output.firstIndex(of: "["),
              let data = String(output[start...]).data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        let entries = raw.compactMap { item -> BrewServiceInfo? in
            guard let name = item["name"] as? String, !name.isEmpty else { return nil }
            let statusText = (item["status"] as? String)?.lowercased() ?? "unknown"
            return BrewServiceInfo(
                name: name,
                serviceName: item["service_name"] as? String,
                status: BrewServiceInfo.Status(rawValue: statusText) ?? .unknown,
                running: item["running"] as? Bool ?? false,
                loaded: item["loaded"] as? Bool ?? false,
                schedulable: item["schedulable"] as? Bool ?? false,
                registered: item["registered"] as? Bool ?? false,
                pid: item["pid"] as? Int,
                exitCode: item["exit_code"] as? Int,
                user: item["user"] as? String,
                file: item["file"] as? String,
                loadedFile: item["loaded_file"] as? String,
                command: item["command"] as? String,
                workingDir: item["working_dir"] as? String,
                rootDir: item["root_dir"] as? String,
                logPath: item["log_path"] as? String,
                errorLogPath: item["error_log_path"] as? String,
                interval: item["interval"] as? String,
                cron: item["cron"] as? String
            )
        }

        return entries.sorted {
            if $0.sortWeight != $1.sortWeight { return $0.sortWeight < $1.sortWeight }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
