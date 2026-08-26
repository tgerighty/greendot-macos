public enum Severity: String, Codable, Equatable, Sendable {
    case red
    case yellow
    case green
    case grey

    public var displayName: String {
        switch self {
        case .green: return "Operational"
        case .yellow: return "Degraded"
        case .red: return "Major outage"
        case .grey: return "Unreachable"
        }
    }
}

public enum Aggregator {
    public static func fromSeverities(_ severities: [Severity]) -> Severity {
        if severities.contains(.red) { return .red }
        if severities.contains(.yellow) { return .yellow }
        if severities.contains(.green) { return .green }
        if severities.contains(.grey) { return .grey }
        return .green
    }
}
