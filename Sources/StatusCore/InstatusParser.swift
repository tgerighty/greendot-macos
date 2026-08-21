import Foundation

public enum InstatusParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let page = json["page"] as? [String: Any],
              let status = page["status"] as? String else {
            throw ParserError.notThisProvider
        }
        if page["indicator"] != nil {
            throw ParserError.notThisProvider
        }
        let name = (page["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host ?? "Status page"
        let pageURL = (page["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
        let incidentsJSON = json["activeIncidents"] as? [[String: Any]] ?? []
        let incidents = incidentsJSON.compactMap { item -> Incident? in
            guard let title = item["name"] as? String else { return nil }
            return Incident(title: title, url: (item["url"] as? String).flatMap(URL.init(string:)))
        }
        let impacts = incidentsJSON.compactMap { $0["impact"] as? String }
        let componentsJSON = json["components"] as? [[String: Any]] ?? []
        let components: [ComponentStatus] = componentsJSON.compactMap { item in
            guard let componentName = item["name"] as? String else { return nil }
            let raw = (item["status"] as? String) ?? "OPERATIONAL"
            let severity: Severity
            switch raw.uppercased() {
            case "OPERATIONAL", "UP": severity = .green
            case "UNDERMAINTENANCE", "DEGRADEDPERFORMANCE", "PARTIALOUTAGE": severity = .yellow
            case "MAJOROUTAGE": severity = .red
            default: severity = .yellow
            }
            return ComponentStatus(name: componentName, severity: severity, statusText: raw)
        }
        return PageSnapshot(
            name: name,
            url: pageURL,
            provider: .instatus,
            overall: StatusMapping.instatusPage(status, incidentImpacts: impacts),
            components: components,
            incidents: incidents,
            isUnreachable: false
        )
    }
}
