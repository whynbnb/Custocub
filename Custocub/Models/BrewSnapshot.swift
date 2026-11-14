import Foundation

/// Homebrew 快照：记录当时安装的全部 Formula 与 Cask。
/// 与「应用快照」不同，它不包含 GUI 应用，只记录 Homebrew 包。
struct BrewSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var note: String
    var createdAt: Date
    var hostName: String
    var osVersion: String
    var brewVersion: String?
    var prefix: String?
    var formulae: [BrewPackage]
    var casks: [BrewPackage]

    init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        hostName: String = Host.current().localizedName ?? "Mac",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        brewVersion: String? = nil,
        prefix: String? = nil,
        formulae: [BrewPackage],
        casks: [BrewPackage]
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.hostName = hostName
        self.osVersion = osVersion
        self.brewVersion = brewVersion
        self.prefix = prefix
        self.formulae = formulae
        self.casks = casks
    }

    var packages: [BrewPackage] { formulae + casks }

    var packageCount: Int { formulae.count + casks.count }
    var formulaCount: Int { formulae.count }
    var caskCount: Int { casks.count }
    var outdatedCount: Int { packages.count { $0.isOutdated } }
    var pinnedCount: Int { packages.count { $0.isPinned } }

    var formulaNames: [String] { formulae.map(\.name) }
    var caskTokens: [String] { casks.map(\.name) }
}

/// 生成 Brewfile 与安装命令。导出后可以直接交给 `brew bundle` 或复制执行。
/// Brewfile 与安装命令使用同一个包名列表，保证导出内容与实际安装结果一致。
enum BrewfileBuilder {
    static func text(
        formulae: [String],
        casks: [String],
        header: String? = nil
    ) -> String {
        var lines: [String] = []
        if let header {
            lines.append("# \(header)")
            lines.append("")
        }
        for name in formulae {
            lines.append("brew \"\(escaped(name))\"")
        }
        for token in casks {
            lines.append("cask \"\(escaped(token))\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func installCommands(formulae: [String], casks: [String]) -> String {
        var lines: [String] = []
        if !formulae.isEmpty {
            lines.append(BrewPackage.command("install", kind: .formula, names: formulae))
        }
        if !casks.isEmpty {
            lines.append(BrewPackage.command("install", kind: .cask, names: casks))
        }
        return lines.joined(separator: "\n")
    }

    static func plainList(_ names: [String]) -> String {
        names.joined(separator: "\n") + (names.isEmpty ? "" : "\n")
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
