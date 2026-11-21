import AppKit

/// 与 SwiftLens 的集成。
///
/// SwiftLens 是一个独立的应用包检查工具。Custocub 通过 LaunchServices
/// 把目标 `.app` 交给 SwiftLens 打开。这种“用其他应用打开文件”的方式
/// 对沙盒应用同样有效：系统会把目标文件的访问权限一并授予接收方，
/// 不需要 SwiftLens 自己申请额外权限。
enum SwiftLensIntegration {
    static let bundleIdentifier = "me.whynbnb.SwiftLens"

    /// SwiftLens 的安装位置；未安装时为 nil。
    static var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static var isInstalled: Bool {
        applicationURL != nil
    }

    @MainActor
    static func open(appPath: String, store: CustocubStore) {
        guard let applicationURL else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let target = URL(fileURLWithPath: appPath)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [target],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                )
                store.statusMessage = L.t("已用 SwiftLens 打开 · %@", target.lastPathComponent)
            } catch {
                store.errorMessage = L.t("无法使用 SwiftLens 打开：%@", error.localizedDescription)
            }
        }
    }
}
