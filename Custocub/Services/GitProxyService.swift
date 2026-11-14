import Foundation

/// Git 全局配置中的一条代理设置。
struct GitProxyEntry: Identifiable, Hashable, Sendable {
    let key: String
    let value: String

    var id: String { key + "=" + value }
}

/// 读取 `git config` 里的代理配置，仅用于展示与可选的子进程覆盖。
///
/// 使用 `--get-regexp proxy` 可以同时拿到 `http.proxy`、`https.proxy`
/// 以及按 URL 单独设置的 `http.<url>.proxy` 等条目。
enum GitProxyService {
    private static let executablePath = "/usr/bin/git"

    static func loadGlobalProxyEntries() async -> [GitProxyEntry] {
        await Task.detached(priority: .utility) {
            guard let result = run(arguments: ["config", "--global", "--get-regexp", "proxy"]),
                  result.status == 0 || result.status == 1 else {
                return []
            }

            return result.output
                .split(separator: "\n")
                .compactMap { line -> GitProxyEntry? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return nil }
                    let parts = trimmed.split(
                        maxSplits: 1,
                        whereSeparator: { $0 == " " || $0 == "\t" }
                    )
                    guard parts.count == 2 else { return nil }
                    return GitProxyEntry(key: String(parts[0]), value: String(parts[1]))
                }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        }.value
    }

    /// 同步读取 `http.<url>.proxy` 这类按 URL 单独的代理键。
    ///
    /// 这些键比通用的 `http.proxy` 更具体，Git 会让它们优先生效。
    /// 启用「接管 Git 代理」时，需要把它们也覆盖掉，否则
    /// `brew update` 仍可能使用旧配置。
    static func urlSpecificProxyKeys() -> [String] {
        guard let result = run(
            arguments: ["config", "--name-only", "--get-regexp", #"^http\..*\.proxy$"#]
        ), result.status == 0 else {
            return []
        }

        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 执行一次本地 `git config` 读取。失败时返回 nil。
    private static func run(arguments: [String]) -> (output: String, status: Int32)? {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}
