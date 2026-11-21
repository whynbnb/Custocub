import Foundation

struct AppChange: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case added
        case removed
        case updated

        var id: Self { self }

        var title: String {
            switch self {
            case .added: L.t("新增")
            case .removed: L.t("移除")
            case .updated: L.t("更新")
            }
        }

        var symbol: String {
            switch self {
            case .added: "plus.circle.fill"
            case .removed: "minus.circle.fill"
            case .updated: "arrow.triangle.2.circlepath.circle.fill"
            }
        }
    }

    struct FieldChange: Identifiable, Hashable, Sendable {
        enum Field: String, CaseIterable, Sendable {
            case name = "名称"
            case version = "版本"
            case build = "构建号"
            case bundleIdentifier = "Bundle ID"
            case path = "安装位置"
            case resolvedPath = "实际路径"
            case source = "来源"
            case steamAppID = "Steam App ID"
            case ownApp = "开发者的应用"
            case systemType = "应用类型"
            case architecture = "架构"
            case size = "大小"
            case installedAt = "安装时间"
            case updatedAt = "更新时间"
            case minimumSystemVersion = "最低系统版本"

            var title: String { L.t(rawValue) }
        }

        let field: Field
        let oldValue: String
        let newValue: String

        var id: Field { field }
    }

    let id: String
    let kind: Kind
    let before: AppRecord?
    let after: AppRecord?

    var app: AppRecord { after ?? before! }

    var fieldChanges: [FieldChange] {
        guard let before, let after else { return [] }
        var changes: [FieldChange] = []

        func append(_ field: FieldChange.Field, _ oldValue: String?, _ newValue: String?) {
            let oldText = (oldValue?.isEmpty == false) ? oldValue! : L.t("无")
            let newText = (newValue?.isEmpty == false) ? newValue! : L.t("无")
            if oldText != newText {
                changes.append(FieldChange(field: field, oldValue: oldText, newValue: newText))
            }
        }

        append(.name, before.name, after.name)
        append(.version, before.displayVersion, after.displayVersion)
        append(.build, before.build, after.build)
        append(.bundleIdentifier, before.bundleIdentifier, after.bundleIdentifier)
        append(.path, before.path, after.path)
        append(.resolvedPath, before.resolvedPath, after.resolvedPath)
        append(.source, before.source.title, after.source.title)
        append(.steamAppID, before.steamAppID, after.steamAppID)
        append(.ownApp, before.isOwn ? L.t("是") : L.t("否"), after.isOwn ? L.t("是") : L.t("否"))
        append(.systemType, before.typeTitle, after.typeTitle)
        append(.architecture, before.architectureText, after.architectureText)
        if let oldSize = before.sizeInBytes, let newSize = after.sizeInBytes, oldSize != newSize {
            changes.append(FieldChange(
                field: .size,
                oldValue: oldSize.formatted(.byteCount(style: .file)),
                newValue: newSize.formatted(.byteCount(style: .file))
            ))
        }
        append(.installedAt, before.installedAtText, after.installedAtText)
        append(.updatedAt, before.updatedAtText, after.updatedAtText)
        append(.minimumSystemVersion, before.minimumSystemVersion, after.minimumSystemVersion)
        return changes
    }

    /// 两张快照之间图标是否发生变化。
    ///
    /// 当前状态的快照不保存 iconData，缺少图标时视为“未知”，
    /// 不能因为一边是 nil 就把所有应用都标记成图标变化。
    var iconChanged: Bool {
        guard let before, let after,
              let oldIcon = before.iconData, !oldIcon.isEmpty,
              let newIcon = after.iconData, !newIcon.isEmpty else {
            return false
        }
        return oldIcon != newIcon
    }

    var summary: String {
        switch kind {
        case .added:
            return L.t("新增 · 版本 %@", after?.displayVersion ?? L.t("未知"))
        case .removed:
            return L.t("移除 · 版本 %@", before?.displayVersion ?? L.t("未知"))
        case .updated:
            let fields = fieldChanges.map(\.field.title)
            if fields.isEmpty, iconChanged {
                return L.t("图标发生变化")
            }
            return fields.isEmpty
                ? L.t("元数据发生变化")
                : L.t("%@发生变化", fields.joined(separator: L.t("、")))
        }
    }

    /// 忽略快照比较中的易变字段：lastSeenAt 每次扫描都会变；
    /// 当前状态没有 iconData；体积未测量完成时也不应该算变化。
    private static func hasMaterialChange(before: AppRecord, after: AppRecord) -> Bool {
        let oldIcon = before.iconData.flatMap { $0.isEmpty ? nil : $0 }
        let newIcon = after.iconData.flatMap { $0.isEmpty ? nil : $0 }
        if let oldIcon, let newIcon, oldIcon != newIcon {
            return true
        }

        var old = before
        var new = after
        old.lastSeenAt = new.lastSeenAt
        old.iconData = nil
        new.iconData = nil

        if old.sizeInBytes == nil || new.sizeInBytes == nil {
            old.sizeInBytes = nil
            new.sizeInBytes = nil
        }

        return old != new
    }

    static func compare(_ older: AppSnapshot, _ newer: AppSnapshot) -> [AppChange] {
        var oldApps = Dictionary(older.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var newApps = Dictionary(newer.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [AppChange] = []

        // 先按安装路径匹配。
        for path in Set(oldApps.keys).intersection(newApps.keys) {
            guard let before = oldApps.removeValue(forKey: path),
                  let after = newApps.removeValue(forKey: path) else { continue }
            if hasMaterialChange(before: before, after: after) {
                changes.append(AppChange(id: path, kind: .updated, before: before, after: after))
            }
        }

        // 再按唯一的 Bundle ID 匹配，识别被移动过位置的应用。
        let oldByBundleID = Dictionary(grouping: oldApps.values.compactMap { app in
            app.bundleIdentifier.map { ($0, app) }
        }, by: \.0)
        let newByBundleID = Dictionary(grouping: newApps.values.compactMap { app in
            app.bundleIdentifier.map { ($0, app) }
        }, by: \.0)

        for bundleID in Set(oldByBundleID.keys).intersection(newByBundleID.keys) {
            guard oldByBundleID[bundleID]?.count == 1,
                  newByBundleID[bundleID]?.count == 1,
                  let before = oldByBundleID[bundleID]?.first?.1,
                  let after = newByBundleID[bundleID]?.first?.1 else { continue }
            oldApps.removeValue(forKey: before.path)
            newApps.removeValue(forKey: after.path)
            if hasMaterialChange(before: before, after: after) {
                changes.append(AppChange(
                    id: "\(before.path)→\(after.path)",
                    kind: .updated,
                    before: before,
                    after: after
                ))
            }
        }

        changes.append(contentsOf: oldApps.values.map {
            AppChange(id: $0.path, kind: .removed, before: $0, after: nil)
        })
        changes.append(contentsOf: newApps.values.map {
            AppChange(id: $0.path, kind: .added, before: nil, after: $0)
        })

        return changes.sorted {
            $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending
        }
    }
}

/// 应用快照中 Homebrew Cask 列表的变化。
struct BrewCaskChange: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case added
        case removed
        case updated

        var id: Self { self }

        var title: String {
            switch self {
            case .added: L.t("新增")
            case .removed: L.t("移除")
            case .updated: L.t("更新")
            }
        }

        var symbol: String {
            switch self {
            case .added: "plus.circle.fill"
            case .removed: "minus.circle.fill"
            case .updated: "arrow.triangle.2.circlepath.circle.fill"
            }
        }
    }

    let id: String
    var kind: Kind
    var token: String
    var name: String?
    var beforeVersion: String?
    var afterVersion: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return token
    }

    static func compare(_ older: AppSnapshot, _ newer: AppSnapshot) -> [BrewCaskChange] {
        let oldCasks = Dictionary(older.casks.map { ($0.token.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let newCasks = Dictionary(newer.casks.map { ($0.token.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        var changes: [BrewCaskChange] = []

        for key in Set(oldCasks.keys).intersection(newCasks.keys) {
            guard let before = oldCasks[key], let after = newCasks[key] else { continue }
            guard before.version != after.version else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .updated,
                token: after.token,
                name: after.name,
                beforeVersion: before.version,
                afterVersion: after.version
            ))
        }

        for key in Set(oldCasks.keys).subtracting(newCasks.keys) {
            guard let before = oldCasks[key] else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .removed,
                token: before.token,
                name: before.name,
                beforeVersion: before.version,
                afterVersion: nil
            ))
        }

        for key in Set(newCasks.keys).subtracting(oldCasks.keys) {
            guard let after = newCasks[key] else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .added,
                token: after.token,
                name: after.name,
                beforeVersion: nil,
                afterVersion: after.version
            ))
        }

        return changes.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

enum ComparisonReport {
    static func markdown(older: AppSnapshot, newer: AppSnapshot, changes: [AppChange]) -> String {
        let added = changes.count { $0.kind == .added }
        let removed = changes.count { $0.kind == .removed }
        let updated = changes.count { $0.kind == .updated }

        var lines = [
            L.t("# Custocub 应用快照对比报告"),
            "",
            L.t("- 较早快照：%@（%@）", older.name, older.createdAt.formatted(date: .long, time: .shortened)),
            L.t("- 较晚快照：%@（%@）", newer.name, newer.createdAt.formatted(date: .long, time: .shortened)),
            L.t("- 变更汇总：新增 %d，移除 %d，更新 %d", added, removed, updated),
            ""
        ]

        for kind in AppChange.Kind.allCases {
            let matches = changes.filter { $0.kind == kind }
            guard !matches.isEmpty else { continue }
            lines.append(L.t("## %@（%d）", kind.title, matches.count))
            lines.append("")

            for change in matches {
                lines.append("### \(change.app.name)")
                lines.append("")
                lines.append(L.t("- Bundle ID：%@", change.app.bundleIdentifier ?? L.t("未知")))
                if let steamAppID = change.app.steamAppID {
                    lines.append(L.t("- Steam App ID：%@", steamAppID))
                }
                lines.append(L.t("- 来源：%@", change.app.source.title))
                lines.append(L.t("- 类型：%@", change.app.typeTitle))
                lines.append(L.t("- 架构：%@", change.app.architectureText))

                switch kind {
                case .added, .removed:
                    lines.append(L.t("- 版本：%@", change.app.displayVersion))
                    lines.append(L.t("- 大小：%@", change.app.displaySize))
                    lines.append(L.t("- 安装位置：%@", change.app.path))
                case .updated:
                    for field in change.fieldChanges {
                        lines.append(L.t("- %@：%@ → %@", field.field.title, field.oldValue, field.newValue))
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}

/// Homebrew 快照之间的对比。
enum BrewComparisonReport {
    static func changes(older: BrewSnapshot, newer: BrewSnapshot) -> [BrewCaskChange] {
        let oldPackages = Dictionary(older.packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newPackages = Dictionary(newer.packages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var changes: [BrewCaskChange] = []
        for key in Set(oldPackages.keys).intersection(newPackages.keys) {
            guard let before = oldPackages[key], let after = newPackages[key] else { continue }
            guard before.installedVersion != after.installedVersion else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .updated,
                token: after.name,
                name: after.kind == .cask ? after.displayName : after.name,
                beforeVersion: before.installedVersion,
                afterVersion: after.installedVersion
            ))
        }
        for key in Set(oldPackages.keys).subtracting(newPackages.keys) {
            guard let before = oldPackages[key] else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .removed,
                token: before.name,
                name: before.kind == .cask ? before.displayName : before.name,
                beforeVersion: before.installedVersion,
                afterVersion: nil
            ))
        }
        for key in Set(newPackages.keys).subtracting(oldPackages.keys) {
            guard let after = newPackages[key] else { continue }
            changes.append(BrewCaskChange(
                id: key,
                kind: .added,
                token: after.name,
                name: after.kind == .cask ? after.displayName : after.name,
                beforeVersion: nil,
                afterVersion: after.installedVersion
            ))
        }
        return changes.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
