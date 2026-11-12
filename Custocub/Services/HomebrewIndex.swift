import Foundation

/// 启动时一次性建立 Homebrew Cask 索引，避免为每个应用执行 brew 命令。
struct HomebrewIndex: Sendable {
    static let caskroomRoots = [
        "/opt/homebrew/Caskroom",
        "/usr/local/Caskroom",
        "/home/linuxbrew/.linuxbrew/Caskroom"
    ]

    let appNames: Set<String>
    let caskNames: Set<String>

    static func build() -> HomebrewIndex {
        let fileManager = FileManager.default
        var appNames = Set<String>()
        var caskNames = Set<String>()

        for root in caskroomRoots where fileManager.fileExists(atPath: root) {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)

            // Cask 目录名就是 cask token。
            if let casks = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for cask in casks {
                    caskNames.insert(cask.lastPathComponent.lowercased())
                }
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                appNames.insert(url.lastPathComponent.lowercased())
                enumerator.skipDescendants()
            }
        }

        return HomebrewIndex(appNames: appNames, caskNames: caskNames)
    }

    func contains(appURL: URL, resolvedPath: String) -> Bool {
        let resolved = resolvedPath.lowercased()
        if resolved.contains("/caskroom/") { return true }
        if appURL.path.lowercased().contains("/caskroom/") { return true }

        let bundleName = appURL.lastPathComponent.lowercased()
        if appNames.contains(bundleName) { return true }

        // 某些 cask 的 app 文件名和 token 不同，但通常包含 token。
        let normalizedName = bundleName
            .replacingOccurrences(of: ".app", with: "")
            .replacingOccurrences(of: " ", with: "-")
        return caskNames.contains(normalizedName)
    }
}
