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

public struct WatchedPage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var url: URL
    public var name: String
    public var notificationsEnabled: Bool
    public var snapshot: PageSnapshot?

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        notificationsEnabled: Bool = true,
        snapshot: PageSnapshot? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.notificationsEnabled = notificationsEnabled
        self.snapshot = snapshot
    }
}
