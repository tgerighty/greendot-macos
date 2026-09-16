import Foundation

public enum IncidentioParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["summary"] as? [String: Any] else {
            throw ParserError.notThisProvider
        }
        let name = JSONScalar.nonempty(summary["name"] as? String)
            ?? sourceURL.host
            ?? "Status page"
        let pageURL = (summary["public_url"] as? String).flatMap(URL.init(string:))
            ?? ProviderProbe.normalizedBase(sourceURL)
        let components = (summary["ongoing_incidents"] as? [[String: Any]] ?? []).compactMap(incidentGroup)
        return PageSnapshot(
            name: name,
            url: pageURL,
            provider: .incidentio,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func incidentGroup(_ item: [String: Any]) -> ComponentStatus? {
        guard let id = JSONScalar.nonempty(item["id"] as? String) else { return nil }
        let mapped = StatusMapping.incidentioImpact(item["impact"] as? String ?? item["status"] as? String)
        let name = JSONScalar.nonempty(item["name"] as? String)
            ?? JSONScalar.nonempty(item["title"] as? String)
            ?? id
        let affected = item["affected_components"] as? [[String: Any]] ?? []
        let children = affected.compactMap { component -> ComponentStatus? in
            let childName = JSONScalar.nonempty(component["name"] as? String)
            guard let childName else { return nil }
            return ComponentStatus(
                name: childName,
                severity: mapped.severity,
                statusText: mapped.text,
                id: JSONScalar.nonempty(component["id"] as? String) ?? childName
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
