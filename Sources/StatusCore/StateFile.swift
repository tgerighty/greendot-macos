import Foundation

/// `state.json`. The machine-local cache. `config.json` holds settings only.
struct StateFile: Codable {
    enum CodingKeys: String, CodingKey {
        case version, didSetLaunchAtLogin, snapshots
    }

    var version: Int
    var didSetLaunchAtLogin: Bool
    var snapshots: [String: PageSnapshot]

    init(
        version: Int = AppConfig.currentVersion,
        didSetLaunchAtLogin: Bool,
        snapshots: [String: PageSnapshot]
    ) {
        self.version = version
        self.didSetLaunchAtLogin = didSetLaunchAtLogin
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? false
        snapshots = try container.decodeIfPresent([String: PageSnapshot].self, forKey: .snapshots) ?? [:]
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
