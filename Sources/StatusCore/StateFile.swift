import Foundation

/// One cached poll result and the page url it came from.
struct PageState: Codable {
    var url: URL
    var snapshot: PageSnapshot
}

/// `state.json`. The machine-local cache. `config.json` holds settings only.
struct StateFile: Codable {
    enum CodingKeys: String, CodingKey {
        case version, didSetLaunchAtLogin, snapshots
    }

    var version: Int
    var didSetLaunchAtLogin: Bool
    var snapshots: [String: PageState]

    init(
        version: Int = AppConfig.currentVersion,
        didSetLaunchAtLogin: Bool,
        snapshots: [String: PageState]
    ) {
        self.version = version
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        // Every state file greendot writes carries this key. A file without it still proves a prior launch.
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? true
        snapshots = try container.decodeIfPresent([String: PageState].self, forKey: .snapshots) ?? [:]
    }
}

extension AppConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case version, pollSeconds, pages, didSetLaunchAtLogin
    }

    /// `didSetLaunchAtLogin` is read for version-1 files only. `state.json` wins when it exists.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        // try? swallows a wrong JSON type so a bad pollSeconds falls back to the default instead of
        // failing the load.
        let rawPollSeconds = (try? container.decodeIfPresent(TimeInterval.self, forKey: .pollSeconds)) ?? nil
        pollSeconds = AppConfig.validPollSeconds(rawPollSeconds)
        pages = try container.decodeIfPresent([WatchedPage].self, forKey: .pages) ?? []
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pollSeconds, forKey: .pollSeconds)
        try container.encode(pages, forKey: .pages)
    }
}
