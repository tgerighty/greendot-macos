import Foundation

public enum StatusProvider: String, Codable, Equatable, Sendable {
    case statuspage
    case statuspal
    case instatus
}

public struct ComponentStatus: Codable, Equatable, Sendable {
    public var name: String
    public var severity: Severity
    public var statusText: String

    public init(name: String, severity: Severity, statusText: String) {
        self.name = name
        self.severity = severity
        self.statusText = statusText
    }
}

public struct Incident: Codable, Equatable, Sendable {
    public var title: String
    public var url: URL?

    public init(title: String, url: URL? = nil) {
        self.title = title
        self.url = url
    }
}

public struct PageSnapshot: Codable, Equatable, Sendable {
    public var name: String
    public var url: URL
    public var provider: StatusProvider
    public var overall: Severity
    public var components: [ComponentStatus]
    public var incidents: [Incident]
    public var isUnreachable: Bool

    public init(
        name: String,
        url: URL,
        provider: StatusProvider,
        overall: Severity,
        components: [ComponentStatus],
        incidents: [Incident],
        isUnreachable: Bool
    ) {
        self.name = name
        self.url = url
        self.provider = provider
        self.overall = overall
        self.components = components
        self.incidents = incidents
        self.isUnreachable = isUnreachable
    }
}

public struct WatchedPage: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var url: URL
    public var name: String
    public var notificationsEnabled: Bool
    public var disabledComponentNames: Set<String>
    public var snapshot: PageSnapshot?

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        notificationsEnabled: Bool = true,
        disabledComponentNames: Set<String> = [],
        snapshot: PageSnapshot? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.notificationsEnabled = notificationsEnabled
        self.disabledComponentNames = disabledComponentNames
        self.snapshot = snapshot
    }

    public var enabledComponents: [ComponentStatus] {
        snapshot?.components.filter { !disabledComponentNames.contains($0.name) } ?? []
    }

    public var displaySeverity: Severity {
        if snapshot?.isUnreachable == true { return .grey }
        return Aggregator.severity(from: enabledComponents)
    }

    public func isComponentEnabled(_ name: String) -> Bool {
        !disabledComponentNames.contains(name)
    }
}

extension WatchedPage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, url, name, notificationsEnabled, disabledComponentNames, snapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        disabledComponentNames = try container.decodeIfPresent(Set<String>.self, forKey: .disabledComponentNames) ?? []
        snapshot = try container.decodeIfPresent(PageSnapshot.self, forKey: .snapshot)
    }
}
