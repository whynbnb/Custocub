import AppKit
import SwiftUI

/// 固定配置。
enum AppConstants {
    /// 开发者的应用使用的 Bundle ID 前缀，固定不可修改。
    static let developerBundlePrefix = "me.whynbnb."

    /// 应用扫描根目录，设置界面会原样展示。
    static let scanDirectories = [
        "/Applications",
        "~/Applications",
        "/System/Applications",
        "/System/Library/CoreServices",
        "/Library/Apple/System/Applications"
    ]
}

/// 多个视图和报告共用的偏好键，避免字符串散落。
enum AppPreferenceKey {
    static let showDeveloperApps = "showDeveloperApps"
}

/// 应用语言。`.system` 跟随 macOS 的语言设置。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    var languageCode: String? {
        switch self {
        case .system: nil
        case .chinese: "zh-Hans"
        case .english: "en"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
    }

    /// 实际生效的语言代码。跟随系统时取系统首选语言。
    var effectiveLanguageCode: String {
        if let code = languageCode { return code }
        return AppLanguage.systemLanguageCode
    }

    /// 系统首选语言里是否包含中文。
    ///
    /// 在应用启动时解析一次并缓存，因为之后切换语言会改写 `AppleLanguages`，
    /// 再查询就得不到真正的「系统」语言了。
    private final class SystemLanguageCache: @unchecked Sendable {
        let lock = NSLock()
        var code: String?
    }

    private static let systemLanguageCache = SystemLanguageCache()

    static var systemLanguageCode: String {
        systemLanguageCache.lock.lock()
        defer { systemLanguageCache.lock.unlock() }
        if let code = systemLanguageCache.code { return code }
        let resolved = resolveSystemLanguageCode()
        systemLanguageCache.code = resolved
        return resolved
    }

    /// 从系统首选语言中解析出 `en` 或 `zh-Hans`。
    private static func resolveSystemLanguageCode() -> String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
    }

    /// 在启动时记录真正的系统语言，供「跟随系统」使用。
    static func cacheSystemLanguage() {
        _ = systemLanguageCode
    }

    /// 启动时把偏好同步给运行时语言覆盖，界面从第一次绘制就是正确语言。
    @MainActor
    static func applyStoredPreference() {
        cacheSystemLanguage()
        LocalizationBundle.install()
        LocalizationBundle.activeLanguage = current.languageCode
    }

    /// 立即切换语言：写入偏好并刷新界面，无需重启。
    @MainActor
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        if let code = language.languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        LocalizationManager.shared.apply(language)
    }
}

/// 应用外观。`.system` 跟随 macOS 的浅色/深色设置。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
    }

    @MainActor
    static func applyStoredPreference() {
        NSApplication.shared.appearance = current.nsAppearance
    }

    @MainActor
    static func set(_ appearance: AppAppearance) {
        UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode")
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}

/// 本地化辅助。中文文案作为 key，英文翻译放在 en.lproj/Localizable.strings。
enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func t(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }
}
