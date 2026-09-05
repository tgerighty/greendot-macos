import Foundation

public enum StatusProvider: String, Codable, Equatable, Sendable {
    case statuspage
    case statuspal
    case instatus
    case flashduty
    case aws
    case rss
}

public struct ComponentStatus: Equatable, Sendable {
    public var id: String
    public var name: String
    public var severity: Severity
    public var statusText: String
    public var children: [ComponentStatus]
    public var isGroup: Bool

    public init(
        name: String,
        severity: Severity,
        statusText: String,
        id: String? = nil,
        children: [ComponentStatus] = [],
        isGroup: Bool = false
    ) {
        self.id = id ?? name
        self.name = name
        self.severity = severity
        self.statusText = statusText
        self.children = children
        self.isGroup = isGroup
    }
}

extension ComponentStatus: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, severity, statusText, children, isGroup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        severity = try container.decode(Severity.self, forKey: .severity)
        statusText = try container.decode(String.self, forKey: .statusText)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? name
        children = try container.decodeIfPresent([ComponentStatus].self, forKey: .children) ?? []
        isGroup = try container.decodeIfPresent(Bool.self, forKey: .isGroup) ?? false
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

extension Aggregator {
    /// Bar colour: red > yellow > green. Grey wins only when no real status exists.
    public static func barSeverity(from snapshots: [PageSnapshot]) -> Severity {
        fromSeverities(snapshots.map(\.overall))
    }

    public static func severity(from components: [ComponentStatus]) -> Severity {
        fromSeverities(components.map(\.severity))
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
        filterEnabled(snapshot?.components ?? [])
    }

    public var displaySeverity: Severity {
        guard let snapshot else { return .grey }
        if snapshot.isUnreachable { return .grey }
        if snapshot.components.isEmpty { return snapshot.overall }
        return ComponentTree.enabledLeafSeverity(
            in: snapshot.components,
            disabledKeys: disabledComponentNames
        )
    }

    public func isComponentEnabled(_ component: ComponentStatus) -> Bool {
        !disabledComponentNames.contains(component.id) && !disabledComponentNames.contains(component.name)
    }

    private func filterEnabled(_ items: [ComponentStatus]) -> [ComponentStatus] {
        items.compactMap { item in
            guard isComponentEnabled(item) else { return nil }
            var copy = item
            copy.children = filterEnabled(item.children)
            if !copy.children.isEmpty {
                copy.severity = ComponentTree.enabledLeafSeverity(
                    in: copy.children,
                    disabledKeys: []
                )
                copy.statusText = copy.severity.displayName
            } else if item.isGroup, !item.children.isEmpty {
                copy.severity = .green
                copy.statusText = copy.severity.displayName
            }
            return copy
        }
    }

}

extension WatchedPage: Codable {
    enum CodingKeys: String, CodingKey {
        case id, url, name, notificationsEnabled, disabledComponentNames, snapshot
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try container.decodeIfPresent(String.self, forKey: .id)
        id = rawID.flatMap(UUID.init(uuidString:)) ?? UUID()
        url = try container.decode(URL.self, forKey: .url)
        name = try container.decode(String.self, forKey: .name)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        disabledComponentNames = try container.decodeIfPresent(Set<String>.self, forKey: .disabledComponentNames) ?? []
        snapshot = try container.decodeIfPresent(PageSnapshot.self, forKey: .snapshot)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(name, forKey: .name)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(disabledComponentNames.sorted(), forKey: .disabledComponentNames)
    }
}
