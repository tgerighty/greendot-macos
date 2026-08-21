import Foundation

enum ParserError: Error, Equatable, LocalizedError {
    case notThisProvider
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notThisProvider: return "JSON is not this status-page format"
        case .invalidJSON: return "Status page returned invalid JSON"
        }
    }
}

public enum StatuspageParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        let json = try decode(data)
        guard let status = json["status"] as? [String: Any],
              let indicator = status["indicator"] as? String else {
            throw ParserError.notThisProvider
        }
        let page = json["page"] as? [String: Any] ?? [:]
        let name = (page["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host ?? "Status page"
        let pageURL = (page["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
        let componentsJSON = json["components"] as? [[String: Any]] ?? []
        let components: [ComponentStatus] = componentsJSON.compactMap { item in
            if item["group"] as? Bool == true { return nil }
            guard let componentName = item["name"] as? String else { return nil }
            let statusValue = (item["status"] as? String) ?? "operational"
            return ComponentStatus(
                name: componentName,
                severity: StatusMapping.statuspageComponent(statusValue),
                statusText: StatusMapping.statuspageComponentText(statusValue)
            )
        }
        let incidentsJSON = json["incidents"] as? [[String: Any]] ?? []
        let incidents = incidentsJSON.compactMap { item -> Incident? in
            guard let title = item["name"] as? String ?? item["title"] as? String else { return nil }
            let url = (item["shortlink"] as? String ?? item["url"] as? String).flatMap(URL.init(string:))
            return Incident(title: title, url: url)
        }
        return PageSnapshot(
            name: name,
            url: pageURL,
            provider: .statuspage,
            overall: StatusMapping.statuspageIndicator(indicator),
            components: components,
            incidents: incidents,
            isUnreachable: false
        )
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParserError.invalidJSON
        }
        return json
    }
}
