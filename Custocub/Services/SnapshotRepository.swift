import Foundation

/// 每个快照单独存为一个 JSON 文件，重命名或写备注时不需要重写所有历史快照。
///
/// 原始快照 JSON 保留完整图标，作为可移植的源数据；应用启动时只读取
/// `SnapshotCache` 里的轻量副本。轻量副本去掉 PNG，只记录图标指纹和
/// 侧车文件位置，真正显示图标时再按需读取。
struct SnapshotRepository: Sendable {
    let directoryURL: URL

    private static let cacheVersion = 2

    private struct SourceAttributes {
        let size: Int64
        let modified: TimeInterval
    }

    private struct CacheManifest: Codable {
        var version: Int
        var sourceSize: Int64
        var sourceModified: TimeInterval
        var appCount: Int
        var iconCount: Int
    }

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

    private var cacheDirectoryURL: URL {
        directoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("SnapshotCache", isDirectory: true)
    }

    private var iconsDirectoryURL: URL {
        cacheDirectoryURL.appendingPathComponent("Icons", isDirectory: true)
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
            autoreleasepool {
                do {
                    let attributes = try sourceAttributes(file)
                    if let cached = loadCache(
                        sourceURL: file,
                        sourceSize: attributes.size,
                        sourceModified: attributes.modified
                    ) {
                        snapshots.append(cached)
                        return
                    }

                    let full = try decodeSource(file)
                    do {
                        let light = try buildCache(
                            from: full,
                            sourceURL: file,
                            sourceSize: attributes.size,
                            sourceModified: attributes.modified
                        )
                        snapshots.append(light)
                    } catch {
                        // 缓存写入失败不应让快照从界面消失；回退到完整数据，
                        // 下次启动会继续尝试构建缓存。
                        print("[Custocub] 快照缓存构建失败 \(file.lastPathComponent): \(error)")
                        snapshots.append(full)
                    }
                } catch {
                    // 单个损坏的快照文件不应阻止其他历史快照加载。
                    print("[Custocub] 跳过无法读取的快照 \(file.lastPathComponent): \(error)")
                }
            }
        }
        return snapshots
    }

    /// 保存完整快照，同时刷新派生缓存，返回可直接放进内存的轻量快照。
    @discardableResult
    func save(_ snapshot: AppSnapshot) throws -> AppSnapshot {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        var source = snapshot
        for index in source.apps.indices {
            if let data = source.apps[index].iconData, !data.isEmpty {
                source.apps[index].iconFingerprint = SnapshotIconStore.fingerprint(for: data)
            }
            // 原始快照不应依赖派生缓存的位置。
            source.apps[index].iconSnapshotID = nil
        }

        let data = try Self.encoder.encode(source)
        let url = fileURL(for: source.id)
        try data.write(to: url, options: [.atomic])

        let attributes = try sourceAttributes(url)
        do {
            return try buildCache(
                from: source,
                sourceURL: url,
                sourceSize: attributes.size,
                sourceModified: attributes.modified
            )
        } catch {
            // 原始快照已经写成功；缓存失败时仍返回可用的完整快照。
            print("[Custocub] 快照缓存写入失败 \(url.lastPathComponent): \(error)")
            return source
        }
    }

    @discardableResult
    func save(_ snapshots: [AppSnapshot]) throws -> [AppSnapshot] {
        try snapshots.map { try save($0) }
    }

    /// 重命名或更新备注：必须先读回原始完整数据，避免把图标写丢。
    @discardableResult
    func updateMetadata(id: UUID, name: String? = nil, note: String? = nil) throws -> AppSnapshot {
        var snapshot = try decodeSource(fileURL(for: id))
        if let name {
            snapshot.name = name
        }
        if let note {
            snapshot.note = note
        }
        return try save(snapshot)
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: cacheFileURL(for: id))
        try? FileManager.default.removeItem(at: manifestURL(for: id))
        SnapshotIconStore.remove(snapshotID: id, root: iconsDirectoryURL)
    }

    func decodeImport(from url: URL) throws -> [AppSnapshot] {
        let data = try Data(contentsOf: url)
        if let collection = try? Self.decoder.decode([AppSnapshot].self, from: data) {
            return collection
        }
        return [try Self.decoder.decode(AppSnapshot.self, from: data)]
    }

    func export(_ snapshot: AppSnapshot, to url: URL) throws {
        let full = (try? decodeSource(fileURL(for: snapshot.id))) ?? fullSnapshot(from: snapshot)
        try Self.exportEncoder.encode(full).write(to: url, options: [.atomic])
    }

    // MARK: - 派生缓存

    /// 缓存文件比原始快照新、且图标侧车目录存在时才复用。
    private func loadCache(
        sourceURL: URL,
        sourceSize: Int64,
        sourceModified: TimeInterval
    ) -> AppSnapshot? {
        guard let id = UUID(uuidString: sourceURL.deletingPathExtension().lastPathComponent),
              let manifestData = try? Data(contentsOf: manifestURL(for: id)),
              let manifest = try? JSONDecoder().decode(CacheManifest.self, from: manifestData),
              manifest.version == Self.cacheVersion,
              manifest.sourceSize == sourceSize,
              abs(manifest.sourceModified - sourceModified) < 0.001,
              manifest.iconCount == 0
                || FileManager.default.fileExists(
                    atPath: iconsDirectoryURL.appendingPathComponent(id.uuidString).path
                ),
              let data = try? Data(contentsOf: cacheFileURL(for: id)),
              var snapshot = try? Self.decoder.decode(AppSnapshot.self, from: data),
              snapshot.apps.count == manifest.appCount else {
            return nil
        }

        for index in snapshot.apps.indices
        where snapshot.apps[index].iconFingerprint?.isEmpty == false {
            snapshot.apps[index].iconSnapshotID = snapshot.id
        }
        return snapshot
    }

    /// 原始快照 → 轻量缓存：图标写入侧车，PNG 从内存副本中移除。
    private func buildCache(
        from snapshot: AppSnapshot,
        sourceURL: URL,
        sourceSize: Int64,
        sourceModified: TimeInterval
    ) throws -> AppSnapshot {
        var light = snapshot
        var iconCount = 0

        // 重写前清空这个快照的侧车目录，避免旧版本缓存或已变更的
        // 图标文件残留。原图仍完整保存在原始快照 JSON 里。
        try? FileManager.default.removeItem(
            at: iconsDirectoryURL.appendingPathComponent(snapshot.id.uuidString, isDirectory: true)
        )
        SnapshotIconStore.invalidateMemoryCache()

        for index in light.apps.indices {
            let app = light.apps[index]
            if let data = app.iconData, !data.isEmpty {
                try SnapshotIconStore.store(
                    data,
                    snapshotID: snapshot.id,
                    app: app,
                    root: iconsDirectoryURL
                )
                light.apps[index].iconFingerprint = app.iconFingerprint
                    ?? SnapshotIconStore.fingerprint(for: data)
                light.apps[index].iconSnapshotID = snapshot.id
                light.apps[index].iconData = nil
                iconCount += 1
            } else if app.iconFingerprint != nil {
                light.apps[index].iconSnapshotID = snapshot.id
            }
        }

        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(light)
        try data.write(to: cacheFileURL(for: snapshot.id), options: [.atomic])

        let manifest = CacheManifest(
            version: Self.cacheVersion,
            sourceSize: sourceSize,
            sourceModified: sourceModified,
            appCount: light.apps.count,
            iconCount: iconCount
        )
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL(for: snapshot.id), options: [.atomic])
        SnapshotIconStore.invalidateMemoryCache()

        return light
    }

    private func fullSnapshot(from snapshot: AppSnapshot) -> AppSnapshot {
        var full = snapshot
        for index in full.apps.indices {
            let app = full.apps[index]
            let snapshotID = app.iconSnapshotID ?? snapshot.id
            if full.apps[index].iconData == nil,
               let data = SnapshotIconStore.iconData(snapshotID: snapshotID, app: app, root: iconsDirectoryURL) {
                full.apps[index].iconData = data
            }
            full.apps[index].iconSnapshotID = nil
        }
        return full
    }

    private func decodeSource(_ url: URL) throws -> AppSnapshot {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try Self.decoder.decode(AppSnapshot.self, from: data)
    }

    private func sourceAttributes(_ url: URL) throws -> SourceAttributes {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return SourceAttributes(
            size: Int64(values.fileSize ?? 0),
            modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func cacheFileURL(for id: UUID) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(id.uuidString).json")
    }

    private func manifestURL(for id: UUID) -> URL {
        cacheDirectoryURL.appendingPathComponent("\(id.uuidString).manifest.json")
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
