import Foundation
import SwiftUI

/// Homebrew 包类型。Formula 是命令行包，Cask 是带图形界面的应用包。
enum BrewPackageKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case formula
    case cask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }

    var symbol: String {
        switch self {
        case .formula: "terminal.fill"
        case .cask: "shippingbox.fill"
        }
    }

    var color: Color {
        switch self {
        case .formula: .mint
        case .cask: .orange
        }
    }

    /// 命令中用于指定类型的开关。
    var commandFlag: String? {
        self == .cask ? "--cask" : nil
    }
}

/// 一个已安装的 Homebrew 包。
struct BrewPackage: Identifiable, Codable, Hashable, Sendable {
    var kind: BrewPackageKind
    var name: String
    var fullName: String
    var displayName: String?
    var summary: String?
    var homepage: String?
    var tap: String?
    var installedVersion: String?
    var latestVersion: String?
    var isOutdated: Bool
    var isPinned: Bool
    var isInstalledOnRequest: Bool
    var isAutoUpdating: Bool
    var installedAt: Date?
    var dependencies: [String]

    var id: String { "\(kind.rawValue):\(name)" }

    init(
        kind: BrewPackageKind,
        name: String,
        fullName: String? = nil,
        displayName: String? = nil,
        summary: String? = nil,
        homepage: String? = nil,
        tap: String? = nil,
        installedVersion: String? = nil,
        latestVersion: String? = nil,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        isInstalledOnRequest: Bool = true,
        isAutoUpdating: Bool = false,
        installedAt: Date? = nil,
        dependencies: [String] = []
    ) {
        self.kind = kind
        self.name = name
        self.fullName = fullName ?? name
        self.displayName = displayName
        self.summary = summary
        self.homepage = homepage
        self.tap = tap
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.isInstalledOnRequest = isInstalledOnRequest
        self.isAutoUpdating = isAutoUpdating
        self.installedAt = installedAt
        self.dependencies = dependencies
    }

    /// 列表显示用的名称：cask 优先使用完整产品名。
    var title: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return name
    }

    var installedVersionText: String {
        guard let installedVersion, !installedVersion.isEmpty else { return L.t("未知") }
        return installedVersion
    }

    var latestVersionText: String {
        guard let latestVersion, !latestVersion.isEmpty else { return L.t("未知") }
        return latestVersion
    }

    var installedAtText: String {
        installedAt?.formatted(date: .abbreviated, time: .shortened) ?? L.t("未知")
    }

    /// Formula 通常是其他包的依赖，Cask 都视为用户主动安装。
    var isDependency: Bool {
        kind == .formula && !isInstalledOnRequest
    }

    /// 依赖名称可能带 tap 前缀，比较时只取最后一段并忽略大小写。
    static func dependencyKey(for name: String) -> String {
        let lastComponent = name.split(separator: "/").last.map(String.init) ?? name
        return lastComponent.lowercased()
    }

    var dependencyKey: String { Self.dependencyKey(for: name) }

    var installCommand: String {
        Self.command("install", kind: kind, names: [name])
    }

    var uninstallCommand: String {
        Self.command("uninstall", kind: kind, names: [name])
    }

    var upgradeCommand: String { upgradeCommand(policy: .current) }

    /// 升级命令。贪婪模式下带上 `--greedy`，与界面里的策略保持一致。
    func upgradeCommand(policy: BrewUpgradePolicy) -> String {
        Self.command(
            "upgrade",
            kind: kind,
            names: [name],
            extraArguments: policy.arguments(for: "upgrade")
        )
    }

    var reinstallCommand: String {
        Self.command("reinstall", kind: kind, names: [name])
    }

    static func command(
        _ verb: String,
        kind: BrewPackageKind,
        names: [String],
        extraArguments: [String] = []
    ) -> String {
        var parts = ["brew", verb]
        if let flag = kind.commandFlag {
            parts.append(flag)
        }
        parts.append(contentsOf: extraArguments)
        parts.append(contentsOf: names)
        return parts.joined(separator: " ")
    }
}

/// 应用快照中记录的 cask 条目。字段保持精简，方便长期保存和跨版本读取。
struct BrewCaskRecord: Identifiable, Codable, Hashable, Sendable {
    var token: String
    var version: String?
    var name: String?
    var tap: String?

    var id: String { token }

    init(token: String, version: String? = nil, name: String? = nil, tap: String? = nil) {
        self.token = token
        self.version = version
        self.name = name
        self.tap = tap
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case version
        case name
        case tap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decode(String.self, forKey: .token)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tap = try container.decodeIfPresent(String.self, forKey: .tap)
    }
}

/// 本机 Homebrew 包的完整清单。
struct BrewInventory: Codable, Sendable {
    var formulae: [BrewPackage]
    var casks: [BrewPackage]
    var brewVersion: String?
    var prefix: String?
    var updatedAt: Date

    var all: [BrewPackage] { formulae + casks }

    var packageCount: Int { formulae.count + casks.count }
    var outdatedCount: Int { all.count { $0.isOutdated } }
    var pinnedCount: Int { all.count { $0.isPinned } }

    func package(id: String) -> BrewPackage? {
        all.first { $0.id == id }
    }
}
