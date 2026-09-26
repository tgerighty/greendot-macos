import Foundation

public enum HerokuParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let systems = json["status"] as? [[String: Any]] else {
            throw ParserError.notThisProvider
        }
        let systemLeaves = systems.compactMap { item -> ComponentStatus? in
            guard let name = JSONScalar.nonempty(item["system"] as? String) else { return nil }
            let mapped = StatusMapping.heroku(item["status"] as? String)
            return ComponentStatus(
                name: name,
                severity: mapped.severity,
                statusText: mapped.text,
                id: name
            )
        }
        guard json["incidents"] == nil || json["incidents"] is [[String: Any]] else {
            throw ParserError.invalidJSON
        }
        let incidents = (json["incidents"] as? [[String: Any]] ?? []).compactMap { item -> ComponentStatus? in
            guard let id = JSONScalar.stringID(item["id"]) else { return nil }
            let name = JSONScalar.nonempty(item["title"] as? String) ?? id
            return ComponentStatus(
                name: name,
                severity: .red,
                statusText: "Major outage",
                id: id,
                isGroup: true
            )
        }
        guard json["scheduled"] == nil || json["scheduled"] is [[String: Any]] else {
            throw ParserError.invalidJSON
        }
        let inProgress = (json["scheduled"] as? [[String: Any]] ?? []).compactMap { item -> ComponentStatus? in
            guard (item["state"] as? String)?.lowercased() == "in-progress" else { return nil }
            guard let id = JSONScalar.stringID(item["id"]) else { return nil }
            let name = JSONScalar.nonempty(item["title"] as? String) ?? id
            return ComponentStatus(
                name: name,
                severity: .yellow,
                statusText: "Maintenance",
                id: id,
                isGroup: true
            )
        }
        let components = systemLeaves + incidents + inProgress
        return PageSnapshot(
            name: "Heroku",
            url: ProviderProbe.normalizedBase(sourceURL),
            provider: .heroku,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }
}
