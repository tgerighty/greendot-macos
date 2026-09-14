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

    static func icingaHost(_ state: Int?, downtime: Bool) -> (severity: Severity, text: String) {
        if downtime { return (.yellow, "Maintenance") }
        switch state {
        case 0: return (.green, "Operational")
        case 1: return (.red, "Major outage")
        case 2: return (.yellow, "Unreachable")
        default: return (.yellow, "Degraded")
        }
    }

    static func oktaCategory(_ raw: String?) -> (severity: Severity, text: String) {
        switch (raw ?? "").lowercased() {
        case "service degradation", "performance issue", "minor service disruption":
            return (.yellow, "Degraded")
        case "service disruption", "feature disruption", "major service disruption":
            return (.red, "Major outage")
        default:
            return (.yellow, "Degraded")
        }
    }

    static func icingaService(_ state: Int?, downtime: Bool) -> (severity: Severity, text: String) {
        if downtime { return (.yellow, "Maintenance") }
        switch state {
        case 0: return (.green, "Operational")
        case 1: return (.yellow, "Degraded")
        case 2: return (.red, "Major outage")
        case 3: return (.yellow, "Unknown")
        default: return (.yellow, "Degraded")
        }
    }

    private static let rssTokens: [String: (severity: Severity, text: String)] = {
        let green = (severity: Severity.green, text: Severity.green.displayName)
        let yellow = (severity: Severity.yellow, text: Severity.yellow.displayName)
        let red = (severity: Severity.red, text: Severity.red.displayName)
        let maintenance = (severity: Severity.yellow, text: "Maintenance")
        return [
            "available": green, "operational": green, "up": green, "none": green, "resolved": green,
            "servicedegradation": yellow, "degraded": yellow, "degraded_performance": yellow,
            "partial_outage": yellow, "minor": yellow, "disruption": yellow,
            "maintenance": maintenance, "undermaintenance": maintenance,
            "serviceinterruption": red, "full_outage": red, "major_outage": red, "majoroutage": red,
            "critical": red, "major": red, "down": red, "outage": red
        ]
    }()

    static func rss(_ raw: String?, missing: Severity = .green) -> Severity {
        guard let raw, !raw.isEmpty else { return missing }
        return rssTokens[raw.lowercased()]?.severity ?? .yellow
    }

    static func rssKnownToken(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, rssTokens[token.lowercased()] != nil else { return nil }
        return token
    }

    static func rssText(_ raw: String?, missing: Severity = .green) -> String {
        guard let raw, !raw.isEmpty else { return missing.displayName }
        return rssTokens[raw.lowercased()]?.text ?? raw
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
