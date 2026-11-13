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
        append(.size, before.displaySize, after.displaySize)
        append(.installedAt, before.installedAtText, after.installedAtText)
        append(.updatedAt, before.updatedAtText, after.updatedAtText)
        append(.minimumSystemVersion, before.minimumSystemVersion, after.minimumSystemVersion)
        return changes
    }

    var summary: String {
        switch kind {
        case .added:
            return L.t("新增 · 版本 %@", after?.displayVersion ?? L.t("未知"))
        case .removed:
            return L.t("移除 · 版本 %@", before?.displayVersion ?? L.t("未知"))
        case .updated:
            let fields = fieldChanges.map(\.field.title)
            return fields.isEmpty
                ? L.t("元数据发生变化")
                : L.t("%@发生变化", fields.joined(separator: L.t("、")))
        }
    }

    static func compare(_ older: AppSnapshot, _ newer: AppSnapshot) -> [AppChange] {
        var oldApps = Dictionary(older.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var newApps = Dictionary(newer.apps.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var changes: [AppChange] = []

        // 先按安装路径匹配。
        for path in Set(oldApps.keys).intersection(newApps.keys) {
            guard let before = oldApps.removeValue(forKey: path),
                  let after = newApps.removeValue(forKey: path) else { continue }
            if before != after {
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
            if before != after {
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
