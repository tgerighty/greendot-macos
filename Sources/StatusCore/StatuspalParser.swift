import Foundation

public enum StatuspalParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let statusPage = json["status_page"] as? [String: Any] else {
            throw ParserError.notThisProvider
        }
        let name = (statusPage["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? sourceURL.host ?? "Status page"
        let pageURL = (statusPage["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
        let type = json["current_status_type"] as? String ?? statusPage["current_incident_type"] as? String
        let services = json["services"] as? [[String: Any]] ?? []
        let components = flatten(services)
        let incidentsJSON = json["incidents"] as? [[String: Any]] ?? []
        let incidents = incidentsJSON.compactMap { item -> Incident? in
            guard let title = item["title"] as? String else { return nil }
            return Incident(title: title, url: (item["url"] as? String).flatMap(URL.init(string:)))
        }
        return PageSnapshot(
            name: name,
            url: pageURL,
            provider: .statuspal,
            overall: StatusMapping.statuspal(type),
            components: components,
            incidents: incidents,
            isUnreachable: false
        )
    }

    private static func flatten(_ services: [[String: Any]]) -> [ComponentStatus] {
        services.flatMap { service -> [ComponentStatus] in
            let children = service["children"] as? [[String: Any]] ?? []
            if !children.isEmpty {
                return flatten(children)
            }
            guard let name = service["name"] as? String else { return [] }
            let type = service["current_incident_type"] as? String
            let severity = StatusMapping.statuspal(type)
            let text: String
            switch severity {
            case .green: text = "Operational"
            case .yellow: text = type == "scheduled" ? "Maintenance" : "Degraded"
            case .red: text = "Major outage"
            case .grey: text = "Unreachable"
            }
            return [ComponentStatus(name: name, severity: severity, statusText: text)]
        }
    }
}
