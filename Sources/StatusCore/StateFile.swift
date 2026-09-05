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
        case version, pages, didSetLaunchAtLogin
    }

    /// `didSetLaunchAtLogin` is read for version-1 files only. `state.json` wins when it exists.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        pages = try container.decodeIfPresent([WatchedPage].self, forKey: .pages) ?? []
        didSetLaunchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .didSetLaunchAtLogin) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(pages, forKey: .pages)
    }
}
