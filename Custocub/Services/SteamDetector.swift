import Foundation

/// Steam 在 macOS 上会为游戏生成一个很小的启动快捷方式，放在 ~/Applications：
///
///     Game.app/
///       Contents/
///         Info.plist          CFBundleExecutable = run.sh
///         MacOS/run.sh        open steam://run/<AppID>
///         Resources/shortcut.icns
///
/// 这组特征比按游戏名称或 Bundle ID 判断可靠得多。
enum SteamDetector {
    static func shortcutAppID(for appURL: URL, info: [String: Any]) -> String? {
        guard (info["CFBundleExecutable"] as? String) == "run.sh" else { return nil }

        let scriptURL = appURL.appendingPathComponent("Contents/MacOS/run.sh")
        guard let data = try? Data(contentsOf: scriptURL),
              data.count <= 64 * 1024,
              let script = String(data: data, encoding: .utf8),
              let marker = script.range(of: "steam://run/") else {
            return nil
        }

        let appID = script[marker.upperBound...].prefix { $0.isNumber }
        guard !appID.isEmpty else { return nil }
        return String(appID)
    }
}

/// 解析 Steam 库目录，用于识别直接位于 `steamapps/common` 下的真实游戏包。
/// 这个索引不参与游戏分类的必需条件，只作为额外兼容。
struct SteamLibraryIndex: Sendable {
    let commonDirectories: [String]

    static func build() -> SteamLibraryIndex {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let steamRoot = home.appendingPathComponent("Library/Application Support/Steam", isDirectory: true)

        var roots = Set<String>()
        if fileManager.fileExists(atPath: steamRoot.path) {
            roots.insert(steamRoot.path)
        }

        let vdfCandidates = [
            steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf"),
            steamRoot.appendingPathComponent("config/libraryfolders.vdf")
        ]

        for vdf in vdfCandidates {
            guard let data = try? Data(contentsOf: vdf),
                  let text = String(data: data, encoding: .utf8) else { continue }

            let regex = try? NSRegularExpression(pattern: #""path"\s+"([^"]+)""#)
            let range = NSRange(text.startIndex..., in: text)
            regex?.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match,
                      match.numberOfRanges > 1,
                      let pathRange = Range(match.range(at: 1), in: text) else { return }
                let path = String(text[pathRange]).replacingOccurrences(of: "\\\\", with: "\\")
                if !path.isEmpty {
                    roots.insert(path)
                }
            }
        }

        let commonDirectories = roots
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("steamapps/common", isDirectory: true).path }
            .sorted()

        return SteamLibraryIndex(commonDirectories: commonDirectories)
    }

    func contains(resolvedPath: String) -> Bool {
        commonDirectories.contains { common in
            resolvedPath == common || resolvedPath.hasPrefix(common + "/")
        }
    }
}
