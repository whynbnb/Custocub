import AppKit
import Foundation
import SwiftUI

/// 运行时语言覆盖。
///
/// 所有界面文案都通过 `Bundle.main` 解析（`L.t` 走 `NSLocalizedString`，
/// SwiftUI 的 `Text("中文")` 也走同一个入口），因此只要在主 bundle 上
/// 拦截 `localizedString(forKey:value:table:)`，就能在不重启的情况下
/// 立刻切换语言。
final class LocalizationBundle: Bundle, @unchecked Sendable {
    /// 需要跨线程访问的共享状态，统一放在带锁的容器里。
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var overrideLanguage: String?
        var languageBundles: [String: Bundle] = [:]
    }

    private static let state = State()

    /// `nil` 表示跟随系统（交给系统按 AppleLanguages 选择）。
    static var activeLanguage: String? {
        get {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.overrideLanguage
        }
        set {
            state.lock.lock()
            state.overrideLanguage = newValue
            state.lock.unlock()
        }
    }

    /// 语言 -> 对应 .lproj bundle 的映射缓存。
    private static func bundle(for language: String) -> Bundle? {
        state.lock.lock()
        defer { state.lock.unlock() }

        if let cached = state.languageBundles[language] { return cached }
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        state.languageBundles[language] = bundle
        return bundle
    }

    /// 把 `Bundle.main` 替换成这个子类，使所有本地化查询都经过我们。
    static func install() {
        guard Bundle.main.isKind(of: LocalizationBundle.self) == false else { return }
        object_setClass(Bundle.main, LocalizationBundle.self)
    }

    override func localizedString(
        forKey key: String,
        value: String?,
        table tableName: String?
    ) -> String {
        guard let language = Self.activeLanguage,
              let languageBundle = Self.bundle(for: language) else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return languageBundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// 语言切换后通知界面重建，让所有文案重新解析。
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// 每次切换语言递增，界面用 `.id(revision)` 触发整体重建。
    @Published private(set) var revision = 0

    /// 当前界面使用的 locale 标识，注入到 SwiftUI 环境里，
    /// 这样 `Text("中文")` 这类 SwiftUI 本地化也会立刻切换。
    @Published private(set) var localeIdentifier = AppLanguage.systemLanguageCode

    private init() {
        localeIdentifier = AppLanguage.current.effectiveLanguageCode
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    func refresh() {
        revision &+= 1
    }

    /// 立即应用语言，无需重启。
    func apply(_ language: AppLanguage) {
        LocalizationBundle.activeLanguage = language.languageCode
        localeIdentifier = language.effectiveLanguageCode
        refresh()
    }
}
