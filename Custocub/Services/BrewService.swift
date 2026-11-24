import Foundation

/// 一次 brew 命令的执行结果。
struct BrewCommandResult: Sendable {
    var exitCode: Int32
    var wasCancelled: Bool

    var succeeded: Bool { exitCode == 0 && !wasCancelled }
}

/// brew 进程产生的事件流。
enum BrewEvent: Sendable {
    case output(String)
    case finished(BrewCommandResult)
}

/// 可以被取消的 brew 子进程。
final class BrewProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func register(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()

        guard let running, running.isRunning else { return }

        // 先发 SIGINT，让 Homebrew 有机会清理临时文件；超时后再强制结束。
        kill(running.processIdentifier, SIGINT)

        Task.detached {
            try? await Task.sleep(for: .seconds(4))
            if running.isRunning {
                kill(running.processIdentifier, SIGTERM)
            }
            try? await Task.sleep(for: .seconds(2))
            if running.isRunning {
                kill(running.processIdentifier, SIGKILL)
            }
        }
    }
}

/// Homebrew 集成入口：定位 brew、执行命令、读取已安装包清单。
enum BrewService {
    /// 常见安装位置。优先 Apple 芯片默认前缀，其次 Intel 前缀。
    static let executableSearchPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
        "/home/linuxbrew/.linuxbrew/bin/brew"
    ]

    static func locateExecutable() -> URL? {
        let fileManager = FileManager.default
        for path in executableSearchPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        // 便携安装或自定义前缀：从 PATH 中兜底查找。
        let environmentPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        for directory in environmentPaths {
            let candidate = directory + "/brew"
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static var isAvailable: Bool { locateExecutable() != nil }

    /// 启动一条 brew 命令，返回可取消的句柄和实时事件流。
    static func start(
        arguments: [String],
        environment: [String: String] = [:]
    ) -> (handle: BrewProcess, stream: AsyncStream<BrewEvent>) {
        let handle = BrewProcess()
        let (stream, continuation) = AsyncStream<BrewEvent>.makeStream(bufferingPolicy: .unbounded)

        guard let executable = locateExecutable() else {
            continuation.yield(.output(L.t("找不到 Homebrew。请确认已经安装 Homebrew。")))
            continuation.yield(.finished(BrewCommandResult(exitCode: 127, wasCancelled: false)))
            continuation.finish()
            return (handle, stream)
        }

        let streamBox = ContinuationBox(continuation)

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var processEnvironment = ProcessInfo.processInfo.environment
            processEnvironment["HOMEBREW_NO_ENV_HINTS"] = "1"
            processEnvironment["HOMEBREW_NO_ANALYTICS"] = "1"
            processEnvironment["NONINTERACTIVE"] = "1"
            processEnvironment["HOMEBREW_NO_COLOR"] = "1"

            // 与 `brew shellenv` 保持一致：同时补上 prefix/bin 和 prefix/sbin。
            // 只补 bin 会让 `brew doctor` 报告 sbin 缺失，
            // 也会让依赖 sbin 中工具的命令找不到可执行文件。
            if let prefix = installedPrefix(fallbackExecutable: executable) {
                let currentPath = processEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                let components = currentPath.split(separator: ":").map(String.init)

                var prepend: [String] = []
                for directory in [prefix + "/bin", prefix + "/sbin"] where !components.contains(directory) {
                    prepend.append(directory)
                }

                processEnvironment["PATH"] = (prepend + components).joined(separator: ":")
            }

            // 升级策略通过环境变量统一生效：
            // 既影响 `brew upgrade` 的实际范围，也影响 `brew info` / `brew outdated`
            // 判断哪些 Cask 算「可更新」，保证列表与实际执行一致。
            BrewUpgradePolicy.current.apply(to: &processEnvironment)

            // 设置里配置的代理通过环境变量传给 brew 及其派生的 git、curl。
            let proxySettings = BrewProxySettings.current
            for (key, value) in proxySettings.environmentOverrides {
                processEnvironment[key] = value
            }
            // 可选：用应用代理覆盖 brew 子进程里的 Git 代理配置。
            // 按 URL 单独设置的 `http.<url>.proxy` 比通用键更优先，需要一起覆盖。
            let urlSpecificGitKeys = proxySettings.isActive && proxySettings.overridesGitProxy
                ? GitProxyService.urlSpecificProxyKeys()
                : []
            for (key, value) in proxySettings.gitProxyEnvironment(
                merging: processEnvironment,
                additionalKeys: urlSpecificGitKeys
            ) {
                processEnvironment[key] = value
            }

            for (key, value) in environment {
                processEnvironment[key] = value
            }
            process.environment = processEnvironment

            let fileHandle = pipe.fileHandleForReading
            fileHandle.readabilityHandler = { readable in
                let chunk = readable.availableData
                guard !chunk.isEmpty else { return }
                streamBox.continuation.yield(.output(String(decoding: chunk, as: UTF8.self)))
            }

            handle.register(process)

            do {
                try process.run()
            } catch {
                fileHandle.readabilityHandler = nil
                streamBox.continuation.yield(.output(L.t("无法启动 Homebrew：%@", error.localizedDescription)))
                streamBox.continuation.yield(.finished(BrewCommandResult(exitCode: 126, wasCancelled: false)))
                streamBox.continuation.finish()
                return
            }

            // 如果用户在进程真正启动前就点了停止，这里补一次终止。
            if handle.isCancelled {
                kill(process.processIdentifier, SIGINT)
            }

            process.waitUntilExit()
            fileHandle.readabilityHandler = nil

            // 进程退出后把管道里剩余的数据读完。使用非阻塞读取，避免
            // brew 派生的后台进程（例如 services）仍然持有写端时永久阻塞。
            Self.drainNonBlocking(fileHandle) { chunk in
                streamBox.continuation.yield(.output(chunk))
            }
            try? fileHandle.close()

            streamBox.continuation.yield(.finished(BrewCommandResult(
                exitCode: process.terminationStatus,
                wasCancelled: handle.isCancelled
            )))
            streamBox.continuation.finish()
        }

        return (handle, stream)
    }

    /// 静默执行，等待结束后返回完整输出。
    ///
    /// 输出收集放在 detached 任务里：SwiftUI 的 `.task` 在视图消失时会被取消，
    /// 若直接在调用方的任务中迭代事件流，会被提前中断并返回**被截断的输出**，
    /// 进而导致解析结果错误（例如把 doctor 的警告当成「没有问题」）。
    static func runQuiet(arguments: [String]) async -> (output: String, result: BrewCommandResult) {
        let session = start(arguments: arguments)

        return await Task.detached(priority: .userInitiated) {
            var output = ""
            var result = BrewCommandResult(exitCode: -1, wasCancelled: false)

            for await event in session.stream {
                switch event {
                case .output(let chunk):
                    output += chunk
                case .finished(let finished):
                    result = finished
                }
            }

            return (output, result)
        }.value
    }

    /// 非阻塞地读取管道剩余内容，最多等待 1 秒。
    private static func drainNonBlocking(_ handle: FileHandle, yield: (String) -> Void) {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }

        let deadline = Date().addingTimeInterval(1)
        var buffer = [UInt8](repeating: 0, count: 8192)

        while Date() < deadline {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                yield(String(decoding: buffer[0..<count], as: UTF8.self))
                continue
            }
            if count == 0 { break }
            // EAGAIN：暂时没有数据，稍等再试。
            usleep(10_000)
        }

        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags)
        }
    }

    /// Homebrew 安装前缀。优先询问 brew，失败时按可执行文件位置推断。
    private static func installedPrefix(fallbackExecutable: URL) -> String? {
        let brewBinary = fallbackExecutable.path
        // /opt/homebrew/bin/brew -> /opt/homebrew
        let binDirectory = (brewBinary as NSString).deletingLastPathComponent
        let prefix = (binDirectory as NSString).deletingLastPathComponent
        return prefix.isEmpty ? nil : prefix
    }

    // MARK: - 清单读取

    /// 读取已安装的 formula 与 cask 完整清单。
    static func loadInventory() async -> BrewInventory? {
        guard isAvailable else { return nil }

        async let info = runQuiet(arguments: ["info", "--json=v2", "--installed"])
        async let version = runQuiet(arguments: ["--version"])
        async let prefix = runQuiet(arguments: ["--prefix"])
        async let caskList = runQuiet(arguments: ["list", "--cask", "--versions"])

        let infoResult = await info
        let versionResult = await version
        let prefixResult = await prefix
        let caskListResult = await caskList

        guard infoResult.result.succeeded,
              let data = infoResult.output.data(using: .utf8),
              var inventory = decodeInventory(data) else {
            return nil
        }

        // 旧 token 的 cask 不会出现在 `brew info --installed` 中
        // （例如 vnc-viewer 已改名为 realvnc-connect-viewer），
        // 因此用 `brew list --cask --versions` 补齐。命令失败时
        // 输出里可能只有警告/错误，不能当成 cask 列表解析。
        if caskListResult.result.succeeded {
            mergeInstalledCaskList(caskListResult.output, into: &inventory)
        }

        inventory.brewVersion = shortVersion(from: versionResult.output)
        let prefixPath = prefixResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        inventory.prefix = prefixPath.isEmpty ? nil : prefixPath
        inventory.updatedAt = Date()
        return inventory
    }

    /// 把 `brew list --cask --versions` 中出现、但 JSON 里缺失的 cask 补进清单。
    static func mergeInstalledCaskList(_ output: String, into inventory: inout BrewInventory) {
        var known = Set(inventory.casks.map { $0.name.lowercased() })
        var newItems: [BrewPackage] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let token = parts.first.map(String.init) else { continue }
            // brew 偶尔会把 Warning/Error 提示混进同一个管道，只接受
            // 形如 cask token 的行，避免生成 `Error:` 这样的假包。
            guard token.range(
                of: #"^[A-Za-z0-9@+._/-]+$"#,
                options: .regularExpression
            ) != nil else { continue }
            guard !known.contains(token.lowercased()) else { continue }

            known.insert(token.lowercased())
            let version = parts.count > 1 ? String(parts[1]) : nil
            newItems.append(BrewPackage(
                kind: .cask,
                name: token,
                installedVersion: version,
                isInstalledOnRequest: true
            ))
        }

        guard !newItems.isEmpty else { return }
        inventory.casks.append(contentsOf: newItems)
        inventory.casks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func shortVersion(from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.lowercased().hasPrefix("homebrew ") else { continue }
            return text.replacingOccurrences(of: "Homebrew ", with: "")
        }
        return nil
    }

    /// 解析 `brew info --json=v2 --installed`。
    static func decodeInventory(_ data: Data) -> BrewInventory? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var formulae: [BrewPackage] = []
        for item in root["formulae"] as? [[String: Any]] ?? [] {
            guard let name = item["name"] as? String else { continue }
            let installed = (item["installed"] as? [[String: Any]])?.first
            let installedTime = (installed?["time"] as? NSNumber)?.doubleValue
            let versions = item["versions"] as? [String: Any]

            formulae.append(BrewPackage(
                kind: .formula,
                name: name,
                fullName: item["full_name"] as? String,
                displayName: nil,
                summary: item["desc"] as? String,
                homepage: item["homepage"] as? String,
                tap: item["tap"] as? String,
                installedVersion: installed?["version"] as? String,
                latestVersion: versions?["stable"] as? String,
                isOutdated: item["outdated"] as? Bool ?? false,
                isPinned: item["pinned"] as? Bool ?? false,
                isInstalledOnRequest: installed?["installed_on_request"] as? Bool ?? true,
                installedAt: installedTime.map { Date(timeIntervalSince1970: $0) },
                dependencies: item["dependencies"] as? [String] ?? []
            ))
        }

        var casks: [BrewPackage] = []
        for item in root["casks"] as? [[String: Any]] ?? [] {
            guard let token = item["token"] as? String else { continue }
            let installedTime = (item["installed_time"] as? NSNumber)?.doubleValue
            let displayName = (item["name"] as? [String])?.first

            casks.append(BrewPackage(
                kind: .cask,
                name: token,
                fullName: item["full_token"] as? String,
                displayName: displayName,
                summary: item["desc"] as? String,
                homepage: item["homepage"] as? String,
                tap: item["tap"] as? String,
                installedVersion: item["installed"] as? String,
                latestVersion: item["version"] as? String,
                isOutdated: item["outdated"] as? Bool ?? false,
                isPinned: item["pinned"] as? Bool ?? false,
                isInstalledOnRequest: true,
                isAutoUpdating: item["auto_updates"] as? Bool ?? false,
                installedAt: installedTime.map { Date(timeIntervalSince1970: $0) }
            ))
        }

        return BrewInventory(
            formulae: formulae.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            casks: casks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            brewVersion: nil,
            prefix: nil,
            updatedAt: Date()
        )
    }
}

/// 让 AsyncStream 的 continuation 能在任意线程安全使用。
private final class ContinuationBox: @unchecked Sendable {
    let continuation: AsyncStream<BrewEvent>.Continuation

    init(_ continuation: AsyncStream<BrewEvent>.Continuation) {
        self.continuation = continuation
    }
}

extension BrewCaskRecord {
    init(from package: BrewPackage) {
        self.init(
            token: package.name,
            version: package.installedVersion,
            name: package.displayName,
            tap: package.tap
        )
    }
}
