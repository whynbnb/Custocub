import Foundation
import SwiftUI

/// 应用来源。系统应用优先于其他来源，iOS 应用优先于 macOS App Store 应用。
enum AppSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case appStore
    case appStoreIOS
    case homebrew
    case steam
    case jetbrainsToolbox
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L.t("系统应用")
        case .appStore: "App Store"
        case .appStoreIOS: "App Store · iOS"
        case .homebrew: "Homebrew"
        case .steam: "Steam"
        case .jetbrainsToolbox: "JetBrains Toolbox"
        case .manual: L.t("手动安装")
        }
    }

    var shortTitle: String {
        switch self {
        case .system: L.t("系统")
        case .appStore: "App Store"
        case .appStoreIOS: "iOS"
        case .homebrew: "Homebrew"
        case .steam: "Steam"
        case .jetbrainsToolbox: "Toolbox"
        case .manual: L.t("手动")
        }
    }

    var symbol: String {
        switch self {
        case .system: "apple.logo"
        case .appStore: "bag.fill"
        case .appStoreIOS: "iphone.gen3"
        case .homebrew: "mug.fill"
        case .steam: "gamecontroller.fill"
        case .jetbrainsToolbox: "wrench.and.screwdriver.fill"
        case .manual: "shippingbox.fill"
        }
    }

    var color: Color {
        switch self {
        case .system: .secondary
        case .appStore: .blue
        case .appStoreIOS: .indigo
        case .homebrew: .orange
        case .steam: Color(red: 0.16, green: 0.52, blue: 0.78)
        case .jetbrainsToolbox: Color(red: 0.86, green: 0.18, blue: 0.50)
        case .manual: .green
        }
    }

    var isAppStore: Bool {
        self == .appStore || self == .appStoreIOS
    }
}

/// 运行平台。架构来自 Mach-O 头，iOS 应用单独标记。
enum AppPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleSilicon
    case intel
    case universal
    case ios
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSilicon: L.t("Apple 芯片")
        case .intel: "Intel"
        case .universal: L.t("通用")
        case .ios: "iOS"
        case .unknown: L.t("未知")
        }
    }

    var shortTitle: String {
        switch self {
        case .appleSilicon: "arm64"
        case .intel: "x86_64"
        case .universal: "arm64+x64"
        case .ios: "iOS"
        case .unknown: L.t("未知")
        }
    }

    var symbol: String {
        switch self {
        case .appleSilicon: "cpu"
        case .intel: "cpu.fill"
        case .universal: "square.stack.3d.up.fill"
        case .ios: "iphone.gen3"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .appleSilicon: .teal
        case .intel: .blue
        case .universal: .purple
        case .ios: .indigo
        case .unknown: .secondary
        }
    }
}
