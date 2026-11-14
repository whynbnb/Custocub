import Foundation

/// `brew config` 的输出，按行拆成键值对。
struct BrewConfigInfo: Sendable {
    struct Entry: Identifiable, Hashable, Sendable {
        var key: String
        var value: String
        var group: Group

        var id: String { key }

        enum Group: String, CaseIterable, Identifiable, Sendable {
            case version
            case taps
            case paths
            case toolchain
            case system
            case environment

            var id: String { rawValue }

            var title: String {
                switch self {
                case .version: L.t("版本")
                case .taps: L.t("Tap")
                case .paths: L.t("路径")
                case .toolchain: L.t("工具链")
                case .system: L.t("系统")
                case .environment: L.t("环境变量")
                }
            }

            var symbol: String {
                switch self {
                case .version: "tag"
                case .taps: "square.stack.3d.up"
                case .paths: "folder"
                case .toolchain: "hammer"
                case .system: "desktopcomputer"
                case .environment: "slider.horizontal.3"
                }
            }
        }
    }

    var entries: [Entry]
    var rawText: String

    func value(for key: String) -> String? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    func entries(in group: Entry.Group) -> [Entry] {
        entries.filter { $0.group == group }
    }

    /// 只保留实际出现的分组，顺序固定。
    var presentGroups: [Entry.Group] {
        Entry.Group.allCases.filter { group in entries.contains { $0.group == group } }
    }
}

/// `brew doctor` 的一条诊断结果。
struct BrewDoctorFinding: Identifiable, Hashable, Sendable {
    var text: String
    var tier: Int
    var affects: [String]
    var links: [String]
    var remediationText: String?
    var remediationCommands: [String]

    var id: String { text }

    var severity: Severity {
        switch tier {
        case 0: .error
        case 1: .warning
        default: .note
        }
    }

    enum Severity: String, Sendable {
        case error
        case warning
        case note

        var title: String {
            switch self {
            case .error: L.t("错误")
            case .warning: L.t("警告")
            case .note: L.t("提示")
            }
        }

        var symbol: String {
            switch self {
            case .error: "xmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .note: "info.circle.fill"
            }
        }

        var sortOrder: Int {
            switch self {
            case .error: 0
            case .warning: 1
            case .note: 2
            }
        }
    }
}

/// `brew doctor` 的整体结果。
struct BrewDoctorReport: Sendable {
    var findings: [BrewDoctorFinding]
    var rawText: String
    var checkedAt: Date
    var exitCode: Int32

    var isHealthy: Bool { findings.isEmpty }

    /// 与 `brew doctor` 的退出码保持一致：只要有问题就视为非零。
    var warningCount: Int { findings.count { $0.severity == .warning } }
    var errorCount: Int { findings.count { $0.severity == .error } }
    var noteCount: Int { findings.count { $0.severity == .note } }

    var sortedFindings: [BrewDoctorFinding] {
        findings.sorted {
            if $0.severity.sortOrder != $1.severity.sortOrder {
                return $0.severity.sortOrder < $1.severity.sortOrder
            }
            return $0.text.localizedStandardCompare($1.text) == .orderedAscending
        }
    }
}

/// 读取 `brew config` 与 `brew doctor` 的服务层。
enum BrewHealthService {
    /// 读取 Homebrew 配置。命令本身很快。
    static func loadConfig() async -> BrewConfigInfo? {
        guard BrewService.isAvailable else { return nil }
        let result = await BrewService.runQuiet(arguments: ["config"])
        guard result.result.exitCode == 0 else { return nil }
        return parseConfig(result.output)
    }

    /// 运行 `brew doctor`。优先使用 JSON 输出以获得结构化结果，
    /// 旧版 Homebrew 不支持 `--json` 时回退到解析文本。
    static func loadDoctor() async -> BrewDoctorReport? {
        guard BrewService.isAvailable else { return nil }

        let json = await BrewService.runQuiet(arguments: ["doctor", "--json"])
        if let report = parseDoctorJSON(json.output, exitCode: json.result.exitCode) {
            return report
        }

        // 回退：普通文本输出。
        let text = await BrewService.runQuiet(arguments: ["doctor"])
        return parseDoctorText(text.output, exitCode: text.result.exitCode)
    }

    // MARK: - 解析 config

    /// 解析 `brew config` 的 `KEY: value` 行。
    static func parseConfig(_ output: String) -> BrewConfigInfo {
        var entries: [BrewConfigInfo.Entry] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            guard let separator = text.firstIndex(of: ":") else { continue }
            let key = String(text[text.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            entries.append(BrewConfigInfo.Entry(
                key: key,
                value: value.isEmpty ? "—" : value,
                group: group(for: key)
            ))
        }

        return BrewConfigInfo(entries: entries, rawText: output)
    }

    /// 按配置项名称分组，便于界面分区展示。
    private static func group(for key: String) -> BrewConfigInfo.Entry.Group {
        let lower = key.lowercased()

        if lower.hasPrefix("homebrew_version") || lower == "origin" || lower == "head" || lower == "branch" {
            return .version
        }
        if lower.contains("tap") {
            return .taps
        }
        if lower.contains("prefix") || lower.contains("cellar") || lower.contains("repository") {
            return .paths
        }
        if lower.contains("ruby") || lower.contains("clang") || lower.contains("git")
            || lower.contains("curl") || lower.contains("clt") || lower.contains("xcode")
            || lower.contains("metal") || lower == "cpu" {
            return .toolchain
        }
        if lower.contains("macos") || lower.contains("rosetta") || lower.contains("last commit") {
            return .system
        }
        return .environment
    }

    // MARK: - 解析 doctor

    /// 解析 `brew doctor --json`。顶层是 `{ tier, findings: [...] }`。
    static func parseDoctorJSON(_ output: String, exitCode: Int32) -> BrewDoctorReport? {
        // `brew doctor` 可能把提示信息输出到 stderr，stdout 里才是 JSON。
        guard let start = output.firstIndex(of: "{"),
              let data = String(output[start...]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFindings = root["findings"] as? [[String: Any]] else {
            return nil
        }

        let findings = rawFindings.compactMap { item -> BrewDoctorFinding? in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            let remediation = item["remediation"] as? [String: Any]
            return BrewDoctorFinding(
                text: text,
                tier: item["tier"] as? Int ?? 1,
                affects: item["affects"] as? [String] ?? [],
                links: item["links"] as? [String] ?? [],
                remediationText: (remediation?["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                remediationCommands: remediation?["commands"] as? [String] ?? []
            )
        }

        return BrewDoctorReport(
            findings: findings,
            rawText: output,
            checkedAt: Date(),
            exitCode: exitCode
        )
    }

    /// 回退解析：按 `Warning:` / `Error:` 分段读取纯文本输出。
    static func parseDoctorText(_ output: String, exitCode: Int32) -> BrewDoctorReport {
        // 这两行是 Homebrew 固定的免责声明，不属于诊断结果。
        let noise = [
            "Please note that these warnings are just used to help the Homebrew maintainers",
            "with debugging if you file an issue. If everything you use Homebrew for is",
            "working fine: please don't worry or file an issue; just ignore this. Thanks!",
            "Your system is ready to brew."
        ]

        var findings: [BrewDoctorFinding] = []
        var currentText: [String] = []
        var currentTier = 1

        func flush() {
            let text = currentText
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            currentText.removeAll()
            guard !text.isEmpty else { return }

            // 去掉开头的 Warning:/Error: 前缀，标题单独展示。
            var body = text
            var tier = currentTier
            for (prefix, value) in [("Warning: ", 1), ("Error: ", 0)] where body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count))
                tier = value
            }
            guard !body.isEmpty else { return }
            findings.append(BrewDoctorFinding(
                text: body,
                tier: tier,
                affects: [],
                links: [],
                remediationText: nil,
                remediationCommands: []
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            let trimmed = text.trimmingCharacters(in: .whitespaces)

            if noise.contains(trimmed) { continue }

            if trimmed.hasPrefix("Warning: ") || trimmed.hasPrefix("Error: ") {
                flush()
                currentTier = trimmed.hasPrefix("Error: ") ? 0 : 1
                currentText = [trimmed]
            } else if !trimmed.isEmpty {
                currentText.append(text)
            }
        }
        flush()

        return BrewDoctorReport(
            findings: findings,
            rawText: output,
            checkedAt: Date(),
            exitCode: exitCode
        )
    }
}
