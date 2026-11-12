import CoreServices
import Foundation

struct AppScanner: Sendable {
    /// 快速扫描：只解析元数据，不计算体积和图标。返回速度通常在 1 秒以内。
    func scan() async -> [AppRecord] {
        await Task.detached(priority: .userInitiated) {
            Self.scanSynchronously()
        }.value
    }

    private static func scanSynchronously() -> [AppRecord] {
        let started = Date()
        let brewIndex = HomebrewIndex.build()
        let steamIndex = SteamLibraryIndex.build()
        let toolboxIndex = JetBrainsToolboxIndex.build()
        let discovered = discoverApplications()
        let now = Date()

        var records: [AppRecord] = []
        records.reserveCapacity(discovered.count)

        for item in discovered {
            if let record = makeRecord(
                appURL: item.url,
                resolvedURL: item.resolvedURL,
                brewIndex: brewIndex,
                steamIndex: steamIndex,
                toolboxIndex: toolboxIndex,
                now: now
            ) {
                records.append(record)
            }
        }

        records.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        #if DEBUG
        print("[Custocub] 扫描 \(records.count) 个应用，用时 \(String(format: "%.2f", Date().timeIntervalSince(started))) 秒")
        #endif
        return records
    }

    private struct DiscoveredApp {
        let url: URL
        let resolvedURL: URL
    }

    private static func discoverApplications() -> [DiscoveredApp] {
        let fileManager = FileManager.default
        var roots = [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices",
            "/Library/Apple/System/Applications"
        ]
        roots.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path)

        var results: [DiscoveredApp] = []
        var seenResolvedPaths = Set<String>()

        for root in roots {
            guard fileManager.fileExists(atPath: root) else { continue }
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let item = enumerator.nextObject() {
                guard let url = item as? URL else { continue }

                // 不深入 .app 包内部，避免把 Xcode 等应用里的辅助应用重复列出。
                if url.pathExtension.lowercased() != "app" { continue }

                enumerator.skipDescendants()

                let resolved = url.resolvingSymlinksInPath()
                let key = resolved.standardizedFileURL.path.lowercased()
                guard seenResolvedPaths.insert(key).inserted else { continue }

                if fileManager.fileExists(atPath: url.path) || fileManager.fileExists(atPath: resolved.path) {
                    results.append(DiscoveredApp(url: url, resolvedURL: resolved))
                }
            }
        }

        return results
    }

    private struct AppBundleInfo {
        let info: [String: Any]
        let infoURL: URL?
        let bundleRoot: URL
        let isIOS: Bool
        let usesContentsLayout: Bool
        let wrappedAppURL: URL?
        let wrappedAppPath: String?
    }

    private static func makeRecord(
        appURL: URL,
        resolvedURL: URL,
        brewIndex: HomebrewIndex,
        steamIndex: SteamLibraryIndex,
        toolboxIndex: JetBrainsToolboxIndex,
        now: Date
    ) -> AppRecord? {
        let fileManager = FileManager.default
        let bundle = loadBundleInfo(appURL: appURL)
        let info = bundle.info
        let resolvedPath = resolvedURL.standardizedFileURL.path
        let originalPath = appURL.path

        let displayName = stringValue(info["CFBundleDisplayName"])
            ?? stringValue(info["CFBundleName"])
            ?? appURL.deletingPathExtension().lastPathComponent

        let bundleIdentifier = stringValue(info["CFBundleIdentifier"])
        let version = stringValue(info["CFBundleShortVersionString"])
            ?? stringValue(info["CFBundleVersion"])
        let build = stringValue(info["CFBundleVersion"])
        let minimumSystemVersion = stringValue(info["LSMinimumSystemVersion"])

        let executableURL = executableURL(for: bundle, fallbackName: stringValue(info["CFBundleExecutable"]))
        let executablePath = executableURL?.path
        let architectures = executableURL.map { MachOReader.architectures(of: $0) } ?? []

        let isSystem = isSystemPath(originalPath) || isSystemPath(resolvedPath)
        let isIOS = bundle.isIOS
        let isHomebrew = brewIndex.contains(appURL: appURL, resolvedPath: resolvedPath)
        let steamAppID = SteamDetector.shortcutAppID(for: appURL, info: info)
        let isSteam = steamAppID != nil || steamIndex.contains(resolvedPath: resolvedPath)
        let isToolboxApp = toolboxIndex.contains(path: originalPath, resolvedPath: resolvedPath)
        let hasReceipt = hasAppStoreReceipt(
            appURL: appURL,
            resolvedURL: resolvedURL,
            bundle: bundle
        )

        let source: AppSource
        if isSystem {
            source = .system
        } else if isIOS {
            source = .appStoreIOS
        } else if isSteam {
            // Steam 快捷方式的 run.sh + steam://run/<appid> 特征非常明确，
            // 优先于名称可能撞车的 Homebrew Cask 判断。
            source = .steam
        } else if isToolboxApp {
            // 只认 Toolbox state.json 中记录的真实安装路径。
            source = .jetbrainsToolbox
        } else if isHomebrew {
            source = .homebrew
        } else if hasReceipt {
            source = .appStore
        } else {
            source = .manual
        }

        let bundleValues = try? resolvedURL.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .addedToDirectoryDateKey
        ])
        let linkValues = try? appURL.resourceValues(forKeys: [
            .addedToDirectoryDateKey
        ])
        let rootValues = try? bundle.bundleRoot.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .addedToDirectoryDateKey
        ])
        let infoValues = bundle.infoURL.flatMap {
            try? $0.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        }
        let executableValues = executableURL.flatMap {
            try? $0.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        }

        let installedAt = linkValues?.addedToDirectoryDate
            ?? bundleValues?.addedToDirectoryDate
            ?? rootValues?.addedToDirectoryDate
            ?? bundleValues?.creationDate
            ?? rootValues?.creationDate
            ?? infoValues?.creationDate

        let updateCandidates = [
            infoValues?.contentModificationDate,
            executableValues?.contentModificationDate,
            bundleValues?.contentModificationDate,
            rootValues?.contentModificationDate
        ].compactMap { $0 }
        let updatedAt = updateCandidates.max()

        // 极少数 .app 目录没有可读的 Info.plist，仍然保留路径信息。
        if info.isEmpty && !fileManager.fileExists(atPath: resolvedURL.path) {
            return nil
        }

        return AppRecord(
            path: originalPath,
            resolvedPath: resolvedPath,
            name: displayName,
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build,
            executablePath: executablePath,
            source: source,
            isSystemApp: isSystem,
            architectures: architectures,
            isIOSApp: isIOS,
            wrappedAppPath: bundle.wrappedAppPath,
            sizeInBytes: nil,
            installedAt: installedAt,
            updatedAt: updatedAt,
            minimumSystemVersion: minimumSystemVersion,
            iconData: nil,
            lastSeenAt: now,
            steamAppID: steamAppID
        )
    }

    private static func loadBundleInfo(appURL: URL) -> AppBundleInfo {
        let fileManager = FileManager.default

        // 1. 标准 macOS 应用：App.app/Contents/Info.plist
        let contentsInfoURL = appURL.appendingPathComponent("Contents/Info.plist")
        if fileManager.fileExists(atPath: contentsInfoURL.path),
           let info = readInfoPlist(contentsInfoURL) {
            return AppBundleInfo(
                info: info,
                infoURL: contentsInfoURL,
                bundleRoot: appURL,
                isIOS: isIOSInfo(info),
                usesContentsLayout: true,
                wrappedAppURL: nil,
                wrappedAppPath: nil
            )
        }

        // 2. Apple 芯片上运行的 iPhone / iPad 应用：App.app/Wrapper/xxx.app/Info.plist
        let wrapperCandidates = [
            appURL.appendingPathComponent("Wrapper", isDirectory: true),
            appURL.appendingPathComponent("Contents/Wrapper", isDirectory: true)
        ]

        for wrapper in wrapperCandidates {
            if let wrapped = firstApplication(in: wrapper),
               let infoURL = existingInfoPlist(in: wrapped),
               let info = readInfoPlist(infoURL) {
                return AppBundleInfo(
                    info: info,
                    infoURL: infoURL,
                    bundleRoot: wrapped,
                    isIOS: true,
                    usesContentsLayout: false,
                    wrappedAppURL: wrapped,
                    wrappedAppPath: wrapped.path
                )
            }
        }

        // 3. WrappedBundle 符号链接
        let wrappedAlias = appURL.appendingPathComponent("WrappedBundle")
        if fileManager.fileExists(atPath: wrappedAlias.path) {
            let resolved = wrappedAlias.resolvingSymlinksInPath()
            if let infoURL = existingInfoPlist(in: resolved),
               let info = readInfoPlist(infoURL) {
                return AppBundleInfo(
                    info: info,
                    infoURL: infoURL,
                    bundleRoot: resolved,
                    isIOS: true,
                    usesContentsLayout: false,
                    wrappedAppURL: resolved,
                    wrappedAppPath: resolved.path
                )
            }
        }

        // 4. 少数工具型应用直接使用根目录 Info.plist
        let rootInfoURL = appURL.appendingPathComponent("Info.plist")
        if let info = readInfoPlist(rootInfoURL) {
            return AppBundleInfo(
                info: info,
                infoURL: rootInfoURL,
                bundleRoot: appURL,
                isIOS: isIOSInfo(info),
                usesContentsLayout: false,
                wrappedAppURL: nil,
                wrappedAppPath: nil
            )
        }

        return AppBundleInfo(
            info: [:],
            infoURL: nil,
            bundleRoot: appURL,
            isIOS: false,
            usesContentsLayout: true,
            wrappedAppURL: nil,
            wrappedAppPath: nil
        )
    }

    private static func firstApplication(in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return contents
            .filter { $0.pathExtension.lowercased() == "app" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first { existingInfoPlist(in: $0) != nil }
    }

    private static func existingInfoPlist(in appURL: URL) -> URL? {
        let candidates = [
            appURL.appendingPathComponent("Info.plist"),
            appURL.appendingPathComponent("Contents/Info.plist")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func readInfoPlist(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private static func isIOSInfo(_ info: [String: Any]) -> Bool {
        if boolValue(info["LSRequiresIPhoneOS"]) { return true }

        if let platform = stringValue(info["DTPlatformName"])?.lowercased(),
           platform == "iphoneos" || platform == "iphonesimulator" {
            return true
        }

        if let sdk = stringValue(info["DTSDKName"])?.lowercased(),
           sdk.hasPrefix("iphoneos") || sdk.hasPrefix("iphonesimulator") {
            return true
        }

        let supported = (info["CFBundleSupportedPlatforms"] as? [String])?
            .map { $0.lowercased() } ?? []
        if supported.contains("iphoneos") && !supported.contains("macosx") {
            return true
        }

        return false
    }

    private static func executableURL(for bundle: AppBundleInfo, fallbackName: String?) -> URL? {
        guard let name = fallbackName, !name.isEmpty else { return nil }
        let base = bundle.usesContentsLayout
            ? bundle.bundleRoot.appendingPathComponent("Contents/MacOS", isDirectory: true)
            : bundle.bundleRoot
        let url = base.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func hasAppStoreReceipt(
        appURL: URL,
        resolvedURL: URL,
        bundle: AppBundleInfo
    ) -> Bool {
        let fileManager = FileManager.default
        var candidates: [URL] = [
            appURL.appendingPathComponent("Contents/_MASReceipt/receipt"),
            appURL.appendingPathComponent("_MASReceipt/receipt"),
            resolvedURL.appendingPathComponent("Contents/_MASReceipt/receipt"),
            resolvedURL.appendingPathComponent("_MASReceipt/receipt"),
            appURL.appendingPathComponent("Wrapper/iTunesMetadata.plist"),
            appURL.appendingPathComponent("Wrapper/BundleMetadata.plist")
        ]

        if let wrapped = bundle.wrappedAppURL {
            candidates.append(wrapped.appendingPathComponent("_MASReceipt/receipt"))
            candidates.append(wrapped.appendingPathComponent("Contents/_MASReceipt/receipt"))
        }

        if candidates.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            return true
        }

        // Spotlight 元数据兜底。即使收据被清理，也能识别 App Store 应用。
        if let item = MDItemCreate(nil, resolvedURL.path as CFString),
           MDItemCopyAttribute(item, "kMDItemAppStoreAdamID" as CFString) != nil {
            return true
        }

        return false
    }

    private static func isSystemPath(_ path: String) -> Bool {
        path.hasPrefix("/System/")
            || path.hasPrefix("/Library/Apple/")
            || path.hasPrefix("/System/Cryptexes/")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }
}
