import Foundation

/// Homebrew 的升级策略。
///
/// Homebrew 7 的默认行为已经会接管一部分 `auto_updates` 的 Cask：
/// 当应用 bundle 的版本落后于 tap 里的版本时，`brew upgrade` 会一并升级它。
/// 再加上 `--greedy` 会额外处理 `:latest`，这两种行为对只想升级普通包的
/// 用户来说都算「贪婪」。
///
/// 这里把行为显式分成三档，并由 Custocub 统一注入到每次 brew 调用，
/// 这样结果不受用户 shell 里 `HOMEBREW_*` 环境变量的影响。
enum BrewUpgradePolicy: String, CaseIterable, Identifiable, Sendable {
    /// 跟随 Homebrew 默认行为。
    case standard
    /// 非贪婪：完全跳过 `auto_updates` 与 `:latest` 的 Cask。
    case conservative
    /// 贪婪：包含 `auto_updates` 与 `:latest` 的 Cask。
    case greedy

    var id: String { rawValue }

    /// `UserDefaults` 中保存策略的键。
    static let defaultsKey = "brewUpgradePolicy"

    static var current: BrewUpgradePolicy {
        BrewUpgradePolicy(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .standard
    }

    var isGreedy: Bool { self == .greedy }

    var title: String {
        switch self {
        case .standard: L.t("标准")
        case .conservative: L.t("非贪婪")
        case .greedy: L.t("贪婪")
        }
    }

    /// 设置界面里的一句话说明。
    var summary: String {
        switch self {
        case .standard:
            L.t("按 Homebrew 默认行为升级。版本落后的自动更新 Cask 也会一并升级，但不处理 :latest。")
        case .conservative:
            L.t("只升级普通包与明确版本过旧的 Formula，完全跳过自动更新和 :latest 的 Cask。")
        case .greedy:
            L.t("同时升级自动更新与 :latest 的 Cask。")
        }
    }

    /// 更详细的影响说明，用于确认对话框。
    var detail: String {
        switch self {
        case .standard:
            L.t("当前为标准策略：Homebrew 可能接管版本落后的自动更新 Cask。")
        case .conservative:
            L.t("当前为非贪婪策略：自动更新和 :latest 的 Cask 不会被升级。")
        case .greedy:
            L.t("当前为贪婪策略：自动更新和 :latest 的 Cask 也会被升级。")
        }
    }

    var symbol: String {
        switch self {
        case .standard: "equal.circle"
        case .conservative: "hand.raised"
        case .greedy: "flame"
        }
    }

    /// 需要额外传给 brew 的参数。
    ///
    /// 只有 `upgrade` 与 `outdated` 支持 `--greedy`；
    /// `info` 不认这个开关，所以只能靠环境变量影响它的判断。
    func arguments(for command: String) -> [String] {
        guard self == .greedy, command == "upgrade" || command == "outdated" else {
            return []
        }
        return ["--greedy"]
    }

    /// 把策略写入 brew 子进程的环境变量。
    ///
    /// 先移除可能从用户 shell 继承的相关变量，再按策略设置，
    /// 保证界面里选的策略和实际执行的行为一致。
    func apply(to environment: inout [String: String]) {
        environment["HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS"] = nil
        environment["HOMEBREW_UPGRADE_GREEDY"] = nil
        // 按包单独指定贪婪的列表会绕过策略，这里一并清除。
        environment["HOMEBREW_UPGRADE_GREEDY_CASKS"] = nil

        switch self {
        case .standard:
            break
        case .conservative:
            environment["HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS"] = "1"
        case .greedy:
            environment["HOMEBREW_UPGRADE_GREEDY"] = "1"
        }
    }
}
