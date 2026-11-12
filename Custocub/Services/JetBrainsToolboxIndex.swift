import Foundation

/// JetBrains Toolbox 在 state.json 中维护已安装工具的真实路径。
/// 只认这些路径，避免把直接下载安装的同名 JetBrains IDE 误判为 Toolbox 管理。
struct JetBrainsToolboxIndex: Sendable {
    let installLocations: Set<String>
    let resolvedLocations: Set<String>

    static func build() -> JetBrainsToolboxIndex {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let toolboxRoot = home.appendingPathComponent(
            "Library/Application Support/JetBrains/Toolbox",
            isDirectory: true
        )

        var paths = stateInstallLocations(toolboxRoot: toolboxRoot)
        if paths.isEmpty {
            paths = channelInstallLocations(toolboxRoot: toolboxRoot)
        }

        var installLocations = Set<String>()
        var resolvedLocations = Set<String>()

        for path in paths where !path.isEmpty {
            guard fileManager.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            installLocations.insert(url.standardizedFileURL.path)
            resolvedLocations.insert(url.resolvingSymlinksInPath().standardizedFileURL.path)
        }

        return JetBrainsToolboxIndex(
            installLocations: installLocations,
            resolvedLocations: resolvedLocations
        )
    }

    func contains(path: String, resolvedPath: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return installLocations.contains(standardized)
            || installLocations.contains(resolvedPath)
            || resolvedLocations.contains(resolvedPath)
    }

    private static func stateInstallLocations(toolboxRoot: URL) -> Set<String> {
        let stateURL = toolboxRoot.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: stateURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = object["tools"] as? [[String: Any]] else {
            return []
        }

        var paths = Set<String>()
        for tool in tools {
            if let path = tool["installLocation"] as? String, !path.isEmpty {
                paths.insert(path)
            }
        }
        return paths
    }

    /// state.json 不可用时的兜底：channels/*.json 中同样记录了 installationDirectory。
    private static func channelInstallLocations(toolboxRoot: URL) -> Set<String> {
        let channelsURL = toolboxRoot.appendingPathComponent("channels", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: channelsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var paths = Set<String>()
        for file in files where file.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let channel = object["channel"] as? [String: Any],
                  let path = channel["installationDirectory"] as? String,
                  !path.isEmpty else { continue }
            paths.insert(path)
        }
        return paths
    }
}
