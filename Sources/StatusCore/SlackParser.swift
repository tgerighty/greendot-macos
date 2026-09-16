import Foundation

public enum SlackParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw ParserError.notThisProvider
        }
        guard json["active_incidents"] != nil else {
            throw ParserError.notThisProvider
        }
        let components = (json["active_incidents"] as? [[String: Any]] ?? []).compactMap(incidentGroup)
        let overall: Severity
        if components.isEmpty {
            overall = status.lowercased() == "ok" ? .green : .yellow
        } else {
            overall = ComponentTree.enabledLeafSeverity(in: components, disabledKeys: [])
        }
        return PageSnapshot(
            name: "Slack",
            url: ProviderProbe.normalizedBase(sourceURL),
            provider: .slack,
            overall: overall,
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func incidentGroup(_ item: [String: Any]) -> ComponentStatus? {
        guard let id = JSONScalar.stringID(item["id"]) else { return nil }
        let mapped = StatusMapping.slackIncidentType(item["type"] as? String)
        let name = JSONScalar.nonempty(item["title"] as? String) ?? id
        let children = (item["services"] as? [String] ?? []).compactMap { service -> ComponentStatus? in
            let serviceName = service.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !serviceName.isEmpty else { return nil }
            return ComponentStatus(
                name: serviceName,
                severity: mapped.severity,
                statusText: mapped.text,
                id: serviceName
            )
        }
        return ComponentStatus(
            name: name,
            severity: mapped.severity,
            statusText: mapped.text,
            id: id,
            children: children,
            isGroup: true
        )
    }
}
