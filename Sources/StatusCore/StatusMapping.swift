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
