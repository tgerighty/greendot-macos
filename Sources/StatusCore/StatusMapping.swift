enum StatusMapping {
    static func statuspageIndicator(_ indicator: String) -> Severity {
        switch indicator.lowercased() {
        case "none": return .green
        case "minor": return .yellow
        case "major", "critical": return .red
        default: return .yellow
        }
    }

    static func statuspageComponent(_ status: String) -> Severity {
        switch status.lowercased() {
        case "operational": return .green
        case "degraded_performance", "partial_outage", "under_maintenance": return .yellow
        case "major_outage": return .red
        default: return .yellow
        }
    }

    static func statuspageComponentText(_ status: String) -> String {
        switch status.lowercased() {
        case "operational": return "Operational"
        case "degraded_performance": return "Degraded"
        case "partial_outage": return "Partial outage"
        case "under_maintenance": return "Maintenance"
        case "major_outage": return "Major outage"
        default: return status
        }
    }

    static func statuspal(_ type: String?) -> Severity {
        switch type {
        case nil: return .green
        case "minor", "scheduled": return .yellow
        case "major": return .red
        default: return .yellow
        }
    }

    static func flashduty(_ status: String) -> Severity {
        switch status.lowercased() {
        case "operational": return .green
        case "degraded", "partial_outage", "maintenance": return .yellow
        case "full_outage": return .red
        default: return .yellow
        }
    }

    static func aws(_ raw: String?) -> Severity {
        switch raw {
        case "0": return .green
        case "1", "2": return .yellow
        case "3": return .red
        default: return .yellow
        }
    }

    static func awsText(_ raw: String?) -> String {
        switch raw {
        case "0": return "Operational"
        case "1", "2": return "Degraded"
        case "3": return "Major outage"
        case nil, "": return "Degraded"
        default: return raw ?? "Degraded"
        }
    }

    static func rss(_ raw: String?, missing: Severity = .green) -> Severity {
        guard let raw, !raw.isEmpty else { return missing }
        return rssKnownSeverity(raw) ?? .yellow
    }

    static func rssKnownToken(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, rssKnownSeverity(token) != nil else { return nil }
        return token
    }

    private static func rssKnownSeverity(_ raw: String) -> Severity? {
        switch raw.lowercased() {
        case "available", "operational", "up", "none", "resolved":
            return .green
        case "servicedegradation", "degraded", "degraded_performance", "partial_outage",
             "maintenance", "undermaintenance", "minor", "disruption":
            return .yellow
        case "serviceinterruption", "full_outage", "major_outage", "majoroutage",
             "critical", "major", "down", "outage":
            return .red
        default:
            return nil
        }
    }

    static func rssText(_ raw: String?, missing: Severity = .green) -> String {
        guard let raw, !raw.isEmpty else {
            return missing == .green ? "Operational" : missing.displayName
        }
        switch raw.lowercased() {
        case "available", "operational", "up", "none", "resolved":
            return "Operational"
        case "servicedegradation", "degraded", "degraded_performance", "partial_outage", "minor",
             "disruption":
            return "Degraded"
        case "maintenance", "undermaintenance":
            return "Maintenance"
        case "serviceinterruption", "full_outage", "major_outage", "majoroutage",
             "critical", "major", "down", "outage":
            return "Major outage"
        default:
            return raw
        }
    }

    static func instatusPage(_ status: String, incidentImpacts: [String]) -> Severity {
        switch status.uppercased() {
        case "UP": return .green
        case "UNDERMAINTENANCE": return .yellow
        case "HASISSUES":
            let major = incidentImpacts.contains { impact in
                let value = impact.uppercased()
                return value == "MAJOROUTAGE" || value == "CRITICAL"
            }
            return major ? .red : .yellow
        default:
            return .yellow
        }
    }
}
