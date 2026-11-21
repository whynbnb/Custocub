import Foundation

/// 用户创建的自定义应用合集。
struct AppCollection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var note: String = ""
    /// 应用稳定标识：优先 Bundle ID，没有时用安装路径。
    var appKeys: Set<String> = []
    var createdAt: Date = Date()
}
