import AppKit
import SwiftUI

/// 固定配置。
enum AppConstants {
    /// 开发者的应用使用的 Bundle ID 前缀，固定不可修改。
    static let developerBundlePrefix = "me.whynbnb."
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

    /// 在启动时把手动选择的语言同步到 AppleLanguages。
    /// 选择「跟随系统」时不写入/删除，避免覆盖系统的按应用语言设置。
    static func applyStoredPreference() {
        guard let code = current.languageCode else { return }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }

    /// 立即写入偏好；语言本身需要重启后才会生效。
    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        if let code = language.languageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
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

enum AppRestart {
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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
