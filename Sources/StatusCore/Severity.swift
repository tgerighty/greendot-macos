import Foundation

public enum Severity: String, Codable, Equatable, Sendable {
    case red
    case yellow
    case green
    case grey
}

public enum Aggregator {
    /// Bar colour: red > yellow > green. Grey wins only when no real status exists.
    public static func barSeverity(from snapshots: [PageSnapshot]) -> Severity {
        fromSeverities(snapshots.map(\.overall))
    }

    public static func fromSeverities(_ severities: [Severity]) -> Severity {
        if severities.contains(.red) { return .red }
        if severities.contains(.yellow) { return .yellow }
        if severities.contains(.green) { return .green }
        if severities.contains(.grey) { return .grey }
        return .green
    }

    public static func severity(from components: [ComponentStatus]) -> Severity {
        fromSeverities(components.map(\.severity))
    }
}
