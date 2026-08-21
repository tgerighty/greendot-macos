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
        if snapshots.contains(where: { $0.overall == .red }) { return .red }
        if snapshots.contains(where: { $0.overall == .yellow }) { return .yellow }
        if snapshots.contains(where: { $0.overall == .green }) { return .green }
        if snapshots.contains(where: { $0.overall == .grey }) { return .grey }
        return .green
    }
}
