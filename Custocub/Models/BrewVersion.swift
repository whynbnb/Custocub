import Foundation

/// Homebrew 版本号。用于做最低版本限制。
///
/// Homebrew 的版本形如 `7.0.13`、`7.0.13-132-gcbd3ae6`、`4.6.0`。
/// 只需要比较主次版本，因此把非数字后缀直接忽略。
struct BrewVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    /// 原始版本字符串，展示时保留完整信息。
    let rawValue: String

    /// 本应用支持的最低 Homebrew 版本。
    static let minimumSupported = BrewVersion(major: 7, minor: 0, patch: 0)

    init(major: Int, minor: Int = 0, patch: Int = 0, rawValue: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.rawValue = rawValue ?? "\(major).\(minor).\(patch)"
    }

    /// 解析 `brew --version` 的输出。
    ///
    /// 输出首行形如 `Homebrew 7.0.13`；也接受直接传入 `7.0.13`。
    init?(output: String) {
        for line in output.split(separator: "\n") {
            var text = line.trimmingCharacters(in: .whitespaces)

            // 去掉 "Homebrew " 前缀。
            if let range = text.range(of: "Homebrew", options: .caseInsensitive) {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }

            guard let parsed = Self.parse(text) else { continue }
            self = parsed
            return
        }
        return nil
    }

    /// 解析 `7.0.13-132-gcbd3ae6` 这类字符串。
    private static func parse(_ text: String) -> BrewVersion? {
        guard !text.isEmpty else { return nil }

        // 只保留开头的数字与点号。
        var numeric = ""
        for character in text {
            if character.isNumber || character == "." {
                numeric.append(character)
            } else {
                break
            }
        }
        guard !numeric.isEmpty else { return nil }

        let parts = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard let majorPart = parts.first, let major = Int(majorPart) else { return nil }

        let minor = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let patch = parts.count > 2 ? Int(parts[2]) ?? 0 : 0

        // 展示时使用完整的原始值，比较只用到数字部分。
        return BrewVersion(major: major, minor: minor, patch: patch, rawValue: text)
    }

    var description: String { rawValue }

    /// 是否满足本应用的最低版本要求。
    var isSupported: Bool { self >= Self.minimumSupported }

    static func < (lhs: BrewVersion, rhs: BrewVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// 版本限制的说明文案，界面和 README 共用。
    static var requirementText: String {
        String(format: L.t("需要 Homebrew %@ 或更高版本"), minimumSupported.description)
    }
}
