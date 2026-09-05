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
            return AppConfig()
        }
        let decoded: AppConfig
        do {
            decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            throw StoreError.corrupt
        }
        guard decoded.version <= AppConfig.currentVersion else { throw StoreError.corrupt }
        var config = Self.uniquingPageIDs(decoded)
        config.version = AppConfig.currentVersion
        applyState(to: &config)
        if Self.needsIDNormalisation(data) {
            try save(config)
        }
        return config
    }

    /// A cache file that cannot be read is ignored. Settings never depend on it.
    private func applyState(to config: inout AppConfig) {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(StateFile.self, from: data) else { return }
        config.didSetLaunchAtLogin = state.didSetLaunchAtLogin
        for index in config.pages.indices {
            if let snapshot = state.snapshots[config.pages[index].id.uuidString] {
                config.pages[index].snapshot = snapshot
            }
        }
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
        try writeIfChanged(try Self.encoder.encode(config), to: configURL)
        let state = StateFile(
            didSetLaunchAtLogin: config.didSetLaunchAtLogin,
            snapshots: Self.snapshots(of: config)
        )
        try writeIfChanged(try Self.encoder.encode(state), to: stateURL)
    }

    private static func snapshots(of config: AppConfig) -> [String: PageSnapshot] {
        var result: [String: PageSnapshot] = [:]
        for page in config.pages {
            result[page.id.uuidString] = page.snapshot
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
