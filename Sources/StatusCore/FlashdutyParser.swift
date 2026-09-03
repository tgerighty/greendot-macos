import Foundation

public enum FlashdutyParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["schema_version"] != nil,
              let overall = json["overall"] as? [String: Any],
              let status = overall["status"] as? String else {
            throw ParserError.notThisProvider
        }
        let page = json["page"] as? [String: Any] ?? [:]
        let name = (page["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host ?? "Status page"
        let pageURL = (page["url"] as? String).flatMap(URL.init(string:)) ?? sourceURL
        let incidents = events(json["ongoing_incidents"]) + events(json["in_progress_maintenances"])
        return PageSnapshot(
            name: name,
            url: pageURL,
            provider: .flashduty,
            overall: StatusMapping.flashduty(status),
            components: [],
            incidents: incidents,
            isUnreachable: false
        )
    }

    private static func events(_ raw: Any?) -> [Incident] {
        (raw as? [[String: Any]] ?? []).compactMap { item in
            guard let title = item["title"] as? String else { return nil }
            return Incident(title: title, url: (item["url"] as? String).flatMap(URL.init(string:)))
        }
    }
}
