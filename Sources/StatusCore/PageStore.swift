import Foundation

public struct AppConfig: Equatable, Sendable {
    public static let currentVersion = 2
    public static let defaultPollSeconds: TimeInterval = 60
    public var version: Int
    public var pollSeconds: TimeInterval
    public var pages: [WatchedPage]
    public var didSetLaunchAtLogin: Bool

    public init(
        version: Int = currentVersion,
        pollSeconds: TimeInterval = defaultPollSeconds,
        pages: [WatchedPage] = [],
        didSetLaunchAtLogin: Bool = false
    ) {
        self.version = version
        self.pollSeconds = pollSeconds
        self.pages = pages
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
    }

    /// Missing, non-finite, or zero and below becomes the default.
    public static func validPollSeconds(_ value: TimeInterval?) -> TimeInterval {
        guard let value, value.isFinite, value > 0 else { return defaultPollSeconds }
        return value
    }
}

public enum StoreError: Error, Equatable, LocalizedError {
    case corrupt

    public var errorDescription: String? {
        switch self {
        case .corrupt:
            return "The saved status list could not be read."
        }
    }
}

public final class PageStore: @unchecked Sendable {
    public let configURL: URL
    public let stateURL: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.configURL = directory.appendingPathComponent("config.json")
        self.stateURL = directory.appendingPathComponent("state.json")
    }

    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["GREENDOT_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("greendot", isDirectory: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public func load() throws -> AppConfig {
        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            let nsError = error as NSError
            guard nsError.domain == NSCocoaErrorDomain,
                  nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError else {
                throw error
            }
            // No pages, so no snapshots attach. The launch flag still belongs to the user.
            var config = AppConfig()
            tightenPermissions()
            applyState(to: &config)
            return config
        }
        tightenPermissions()
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw StoreError.corrupt
        }
        guard decoded.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        var config = Self.uniquingPageIDs(Self.strippingLegacyState(decoded))
        config.version = AppConfig.currentVersion
        applyState(to: &config)
        if Self.needsIDNormalisation(data) {
            // Best effort. The ids are already unique in memory; the next successful save persists them.
            try? save(config)
        }
        return config
    }

    /// A file copied in from another machine can carry a wider mode. A feed url can hold a token.
    /// Best effort: a read-only volume or a foreign owner must not fail the load.
    private func tightenPermissions() {
        if isRegularFile(configURL) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        }
        if isRegularFile(stateURL) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
        }
    }

    /// Only files. A directory left at a path needs its execute bit so save can clear it.
    /// A `URL` caches its resource values, so ask the file system instead.
    private func isRegularFile(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeRegular
    }

    /// A cache file that cannot be read is ignored. Settings never depend on it.
    private func applyState(to config: inout AppConfig) {
        let exists = FileManager.default.fileExists(atPath: stateURL.path)
        guard let data = try? Data(contentsOf: stateURL) else {
            // A file that exists but cannot be read still proves the app has run before.
            if exists { config.didSetLaunchAtLogin = true }
            return
        }
        guard let state = try? JSONDecoder().decode(StateFile.self, from: data) else {
            // A file that cannot be decoded can only exist when the app has run before.
            config.didSetLaunchAtLogin = true
            return
        }
        config.didSetLaunchAtLogin = state.didSetLaunchAtLogin
        for index in config.pages.indices {
            guard let entry = state.snapshots[config.pages[index].id.uuidString] else { continue }
            // A cached result belongs to the url it was polled from. A hand-edited url drops it.
            config.pages[index].snapshot = entry.url == config.pages[index].url ? entry.snapshot : nil
        }
    }

    /// Version 2 keeps machine-local data in state.json only. Inline copies in a shared file are stale.
    /// A version-1 file keeps its inline data, which `applyState` then migrates.
    private static func strippingLegacyState(_ config: AppConfig) -> AppConfig {
        guard config.version >= 2 else { return config }
        var next = config
        next.didSetLaunchAtLogin = false
        for index in next.pages.indices {
            next.pages[index].snapshot = nil
        }
        return next
    }

    /// Keeps every page. The second and later pages with a repeated id get a fresh one.
    /// This must agree with `needsIDNormalisation`. Both compare parsed `UUID`s. Change the two together.
    private static func uniquingPageIDs(_ config: AppConfig) -> AppConfig {
        var next = config
        var seen: Set<UUID> = []
        for index in next.pages.indices where !seen.insert(next.pages[index].id).inserted {
            let fresh = UUID()
            next.pages[index].id = fresh
            seen.insert(fresh)
        }
        return next
    }

    /// True when a page has no id, an id string that is not a UUID, or an id another page also uses.
    /// This must agree with `uniquingPageIDs`. Both compare parsed `UUID`s. Change the two together.
    private static func needsIDNormalisation(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = root["pages"] as? [[String: Any]] else { return false }
        var seen: Set<UUID> = []
        for page in pages {
            guard let raw = page["id"] as? String, let parsed = UUID(uuidString: raw) else { return true }
            guard seen.insert(parsed).inserted else { return true }
        }
        return false
    }

    public func save(_ config: AppConfig) throws {
        try validate(config)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        clearDirectoryAtStatePath()
        let previousConfig: Data?
        do {
            previousConfig = try Data(contentsOf: configURL)
        } catch {
            // A file that exists but cannot be read cannot be rolled back. Refuse to write over it.
            guard !FileManager.default.fileExists(atPath: configURL.path) else { throw error }
            previousConfig = nil
        }
        try writeIfChanged(try Self.encoder.encode(config), to: configURL)
        let state = StateFile(
            didSetLaunchAtLogin: config.didSetLaunchAtLogin,
            snapshots: Self.snapshots(of: config)
        )
        do {
            try writeIfChanged(try Self.encoder.encode(state), to: stateURL)
        } catch {
            restoreConfig(previousConfig)
            throw error
        }
    }

    /// state.json is our cache; a directory in its place is junk we can clear.
    /// Best effort: a directory that stays fails the write below, which rolls the save back.
    private func clearDirectoryAtStatePath() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: stateURL.path)
        guard attributes?[.type] as? FileAttributeType == .typeDirectory else { return }
        try? FileManager.default.removeItem(at: stateURL)
    }

    /// A settings change must not stay on disk when the cache write fails; the app keeps its old
    /// in-memory state. Best effort: the original error is the one the caller sees.
    private func restoreConfig(_ previous: Data?) {
        guard let previous else {
            try? FileManager.default.removeItem(at: configURL)
            return
        }
        try? previous.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static func snapshots(of config: AppConfig) -> [String: PageState] {
        var result: [String: PageState] = [:]
        for page in config.pages {
            guard let snapshot = page.snapshot else { continue }
            result[page.id.uuidString] = PageState(url: page.url, snapshot: snapshot)
        }
        return result
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if (try? Data(contentsOf: url)) != data {
            try data.write(to: url, options: .atomic)
        }
        // Always. A file copied in from another machine can have identical bytes and a wider mode.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func validate(_ config: AppConfig) throws {
        guard config.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        let pageIDs = config.pages.map(\.id)
        guard Set(pageIDs).count == pageIDs.count else { throw StoreError.corrupt }
    }
}
