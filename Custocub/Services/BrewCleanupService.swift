import Foundation

/// Homebrew 缓存、旧版本、无用依赖等清理相关信息的汇总。
///
/// 字段含义参考 Homebrew 源码：
/// - `brew cleanup`：清理过期下载、旧版本 keg、残留锁文件、日志等
/// - `brew autoremove`：卸载「只作为依赖安装、现在不再被需要」的 formula
/// - `brew leaves`：不是任何其他 formula / cask 依赖的 formula
/// - `brew missing`：检查已安装包缺失的依赖
struct BrewCleanupReport: Sendable {
    /// 缓存目录的大小分布。
    struct CacheCategory: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        var bytes: Int64
        var itemCount: Int?
        /// 是否是真正的下载缓存（体量通常最大）。
        var isDownload: Bool = false
    }

    /// 同一 formula 存在多个已安装版本。
    struct OldVersion: Identifiable, Hashable, Sendable {
        var formula: String
        var versions: [String]

        var id: String { formula }

        /// 保留最新版本，其余可以清理。
        var removableVersions: [String] {
            guard versions.count > 1 else { return [] }
            return Array(versions.dropLast())
        }
    }

    var analyzedAt: Date
    var cachePath: String
    var cacheCategories: [CacheCategory]
    var logsPath: String
    var logsBytes: Int64
    var cellarPath: String
    var cellarBytes: Int64

    /// `brew autoremove -n` 报告的可以移除的 formula。
    var unneededFormulae: [String]
    /// 存在多个已安装版本的 formula。
    var oldVersions: [OldVersion]
    /// 不是任何依赖的 formula 数量（对应 `brew leaves`）。
    var leavesCount: Int
    /// 作为依赖安装的 formula 数量。
    var dependencyCount: Int
    /// `brew missing` 报告的缺失依赖，空表示健康。
    var missingDependencies: [String]
    /// `brew cleanup -n` 预计会删除的条目数。
    var pendingCleanupCount: Int
    /// `brew cleanup -n` 预计可释放的空间。
    var estimatedFreeBytes: Int64?
    /// `brew cleanup --prune=all -n` 预计可释放的空间（含最新版本的下载缓存）。
    var deepCleanFreeBytes: Int64?

    var cacheBytes: Int64 {
        cacheCategories.reduce(0) { $0 + $1.bytes }
    }

    var hasAnythingToClean: Bool {
        pendingCleanupCount > 0
            || !unneededFormulae.isEmpty
            || !oldVersions.isEmpty
            || cacheBytes > 0
    }

    var summaryText: String {
        var parts: [String] = []
        if !unneededFormulae.isEmpty {
            parts.append(L.t("%d 个无用依赖", unneededFormulae.count))
        }
        if !oldVersions.isEmpty {
            parts.append(L.t("%d 个旧版本", oldVersions.count))
        }
        if pendingCleanupCount > 0 {
            parts.append(L.t("%d 个缓存条目", pendingCleanupCount))
        }
        return parts.isEmpty ? L.t("没有需要清理的内容") : parts.joined(separator: " · ")
    }
}

/// 执行 Homebrew 清理相关命令的服务层。
enum BrewCleanupService {
    /// 分析当前可清理的内容。
    ///
    /// 只用只读命令（`-n` 试运行、目录大小统计），不会修改任何文件。
    static func analyze() async -> BrewCleanupReport? {
        guard BrewService.isAvailable else { return nil }

        async let cachePathResult = BrewService.runQuiet(arguments: ["--cache"])
        async let prefixResult = BrewService.runQuiet(arguments: ["--prefix"])
        async let autoremoveResult = BrewService.runQuiet(arguments: ["autoremove", "-n"])
        async let listResult = BrewService.runQuiet(arguments: ["list", "--formula", "--versions"])
        async let leavesResult = BrewService.runQuiet(arguments: ["leaves"])
        async let missingResult = BrewService.runQuiet(arguments: ["missing"])

        let cachePathOutput = await cachePathResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixOutput = await prefixResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let autoremoveOutput = await autoremoveResult.output
        let listOutput = await listResult.output
        let leavesOutput = await leavesResult.output
        let missingOutput = await missingResult.output

        let cachePath = cachePathOutput.isEmpty
            ? NSHomeDirectory() + "/Library/Caches/Homebrew"
            : cachePathOutput
        let prefix = prefixOutput.isEmpty ? "/opt/homebrew" : prefixOutput

        let oldVersions = parseOldVersions(listOutput)
        let formulaCount = listOutput.split(separator: "\n").count
        let leavesCount = leavesOutput.split(separator: "\n").count

        // `brew cleanup -n` 与 `--prune=all -n` 都较慢（需要遍历缓存），放在最后。
        async let cleanupDryRun = BrewService.runQuiet(arguments: ["cleanup", "-n"])
        async let deepDryRun = BrewService.runQuiet(arguments: ["cleanup", "--prune=all", "-n"])

        // 目录大小统计在后台线程执行。
        let sizes = await Task.detached(priority: .utility) { () -> (categories: [BrewCleanupReport.CacheCategory], logsBytes: Int64, cellarBytes: Int64) in
            let categories = measureCache(at: cachePath)
            let logsBytes = DirectorySize.bytes(at: URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Homebrew"))
            let cellarBytes = DirectorySize.bytes(at: URL(fileURLWithPath: prefix + "/Cellar"))
            return (categories, logsBytes, cellarBytes)
        }.value

        let dryRunOutput = await cleanupDryRun.output
        let deepOutput = await deepDryRun.output
        let (pendingCount, estimatedFree) = parseCleanupDryRun(dryRunOutput)
        let deepFree = parseCleanupDryRun(deepOutput).bytes

        return BrewCleanupReport(
            analyzedAt: Date(),
            cachePath: cachePath,
            cacheCategories: sizes.categories,
            logsPath: NSHomeDirectory() + "/Library/Logs/Homebrew",
            logsBytes: sizes.logsBytes,
            cellarPath: prefix + "/Cellar",
            cellarBytes: sizes.cellarBytes,
            unneededFormulae: parseAutoremove(autoremoveOutput),
            oldVersions: oldVersions,
            leavesCount: leavesCount,
            dependencyCount: max(0, formulaCount - leavesCount),
            missingDependencies: parseMissing(missingOutput),
            pendingCleanupCount: pendingCount,
            estimatedFreeBytes: estimatedFree,
            deepCleanFreeBytes: deepFree
        )
    }

    // MARK: - 解析

    /// 缓存目录按子目录拆分，方便用户看出空间都被什么占用。
    ///
    /// 对应 Homebrew 缓存结构：`downloads`、`api`、`bootsnap` 等。
    private static func measureCache(at path: String) -> [BrewCleanupReport.CacheCategory] {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: path)

        let displayNames: [String: String] = [
            "downloads": L.t("下载缓存"),
            "api": L.t("API 索引"),
            "bootsnap": L.t("Ruby 编译缓存"),
            "api-source": L.t("API 源")
        ]
        let orderedKeys = ["downloads", "api", "bootsnap", "api-source"]

        var categories: [BrewCleanupReport.CacheCategory] = []
        var measuredRoots = Set<String>()

        for key in orderedKeys {
            let url = root.appendingPathComponent(key, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            measuredRoots.insert(key)

            let bytes = DirectorySize.bytes(at: url)
            let items = (try? fileManager.contentsOfDirectory(atPath: url.path).count)
            categories.append(BrewCleanupReport.CacheCategory(
                id: key,
                name: displayNames[key] ?? key,
                bytes: bytes,
                itemCount: items,
                isDownload: key == "downloads"
            ))
        }

        // 其他零散文件（.json、符号链接、portable-ruby 等）合并统计。
        let rootBytes = DirectorySize.bytes(at: root)
        let knownBytes = categories.reduce(Int64(0)) { $0 + $1.bytes }
        let otherBytes = max(0, rootBytes - knownBytes)
        if otherBytes > 0 {
            categories.append(BrewCleanupReport.CacheCategory(
                id: "other",
                name: L.t("其他文件"),
                bytes: otherBytes,
                itemCount: nil
            ))
        }

        return categories.sorted { $0.bytes > $1.bytes }
    }

    /// 解析 `brew autoremove -n`，取出「Would autoremove N unneeded formulae:」后面的包名。
    static func parseAutoremove(_ output: String) -> [String] {
        var names: [String] = []
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            // 标题行与提示行都跳过。
            if text.hasPrefix("==>") || text.hasPrefix("Warning:") || text.hasPrefix("Error:") { continue }
            if text.contains("unneeded formula") || text.contains("Would autoremove") { continue }
            // 剩下的每一行就是一个包名。
            if !text.contains(" ") {
                names.append(text)
            }
        }
        return names
    }

    /// 解析 `brew list --formula --versions`：`name version1 version2`，多版本即旧版本。
    static func parseOldVersions(_ output: String) -> [BrewCleanupReport.OldVersion] {
        var result: [BrewCleanupReport.OldVersion] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count > 2 else { continue }
            result.append(BrewCleanupReport.OldVersion(
                formula: parts[0],
                versions: Array(parts.dropFirst())
            ))
        }
        return result.sorted { $0.formula.localizedStandardCompare($1.formula) == .orderedAscending }
    }

    /// 解析 `brew missing`。空输出表示没有缺失依赖。
    static func parseMissing(_ output: String) -> [String] {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                if line.hasPrefix("You should") { return false }
                if line.hasPrefix("brew install") { return false }
                if line.hasPrefix("Warning:") { return false }
                return true
            }
        return lines
    }

    /// 解析 `brew cleanup -n`：统计 `Would remove` 行数并提取可释放空间。
    static func parseCleanupDryRun(_ output: String) -> (count: Int, bytes: Int64?) {
        var count = 0
        var bytes: Int64?

        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("Would remove") {
                count += 1
            } else if text.contains("would free approximately") {
                bytes = parseHumanBytes(text)
            }
        }
        return (count, bytes)
    }

    /// 从「approximately 16GB of disk space」中解析出字节数。
    static func parseHumanBytes(_ text: String) -> Int64? {
        guard let range = text.range(of: "approximately") else { return nil }
        let remainder = text[range.upperBound...]
        guard let token = remainder.split(separator: " ").first else { return nil }

        let value = String(token).trimmingCharacters(in: .whitespaces)
        let units: [(suffix: String, multiplier: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000),
            ("B", 1)
        ]
        for (suffix, multiplier) in units where value.uppercased().hasSuffix(suffix) {
            let number = value.dropLast(suffix.count)
                .replacingOccurrences(of: ",", with: "")
            guard let amount = Double(number) else { continue }
            return Int64(amount * multiplier)
        }
        return nil
    }
}
