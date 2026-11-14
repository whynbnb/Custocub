import Foundation

/// Homebrew 快照单独存储，与应用快照互不干扰。
struct BrewSnapshotRepository: Sendable {
    let directoryURL: URL

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = support
                .appendingPathComponent("Custocub", isDirectory: true)
                .appendingPathComponent("BrewSnapshots", isDirectory: true)
        }
    }

    func load() throws -> [BrewSnapshot] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var snapshots: [BrewSnapshot] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: file)
                snapshots.append(try Self.decoder.decode(BrewSnapshot.self, from: data))
            } catch {
                print("[Custocub] 跳过无法读取的 Homebrew 快照 \(file.lastPathComponent): \(error)")
            }
        }
        return snapshots
    }

    func save(_ snapshot: BrewSnapshot) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL(for: snapshot.id), options: [.atomic])
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
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
}
