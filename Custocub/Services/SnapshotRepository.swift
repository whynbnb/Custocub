import Foundation

/// 每个快照单独存为一个 JSON 文件，重命名或写备注时不需要重写所有历史快照。
struct SnapshotRepository: Sendable {
    let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = support
                .appendingPathComponent("Custocub", isDirectory: true)
                .appendingPathComponent("Snapshots", isDirectory: true)
        }
    }

    /// 兼容测试或旧调用：传入文件路径时使用它所在目录。
    init(fileURL: URL) {
        self.directoryURL = fileURL.deletingLastPathComponent()
    }

    func load() throws -> [AppSnapshot] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var snapshots: [AppSnapshot] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            // 快照 JSON 通常有十几 MB，且图标是 base64。逐个文件放进
            // autoreleasepool，避免 Foundation 的临时缓冲在循环外累积；
            // mappedIfSafe 让大文件走可回收的映射，而不是常驻堆内存。
            autoreleasepool {
                do {
                    let data = try Data(contentsOf: file, options: [.mappedIfSafe])
                    snapshots.append(try Self.decoder.decode(AppSnapshot.self, from: data))
                } catch {
                    // 单个损坏的快照文件不应阻止其他历史快照加载。
                    print("[Custocub] 跳过无法读取的快照 \(file.lastPathComponent): \(error)")
                }
            }
        }
        return snapshots
    }

    func save(_ snapshot: AppSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.id), options: [.atomic])
    }

    func save(_ snapshots: [AppSnapshot]) throws {
        for snapshot in snapshots {
            try save(snapshot)
        }
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func decodeImport(from url: URL) throws -> [AppSnapshot] {
        let data = try Data(contentsOf: url)
        if let collection = try? Self.decoder.decode([AppSnapshot].self, from: data) {
            return collection
        }
        return [try Self.decoder.decode(AppSnapshot.self, from: data)]
    }

    func export(_ snapshot: AppSnapshot, to url: URL) throws {
        try Self.exportEncoder.encode(snapshot).write(to: url, options: [.atomic])
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let exportEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
