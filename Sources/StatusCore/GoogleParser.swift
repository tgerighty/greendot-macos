import Foundation

public enum GoogleParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ParserError.notThisProvider
        }
        let components = items.compactMap { item -> ComponentStatus? in
            guard let incident = item as? [String: Any] else { return nil }
            return activeIncident(incident)
        }
        return PageSnapshot(
            name: pageName(sourceURL),
            url: ProviderProbe.normalizedBase(sourceURL),
            provider: .google,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func activeIncident(_ item: [String: Any]) -> ComponentStatus? {
        if let end = item["end"] as? String, !end.isEmpty { return nil }
        guard let id = JSONScalar.nonempty(item["id"] as? String) else { return nil }
        let mapped = StatusMapping.googleSeverity(item["severity"] as? String)
        let rawName = JSONScalar.nonempty(item["external_desc"] as? String) ?? id
        let name = rawName.split(whereSeparator: \.isNewline).first.map(String.init) ?? rawName
        let children = (item["affected_products"] as? [[String: Any]] ?? []).compactMap { product -> ComponentStatus? in
            let title = JSONScalar.nonempty(product["title"] as? String)
                ?? JSONScalar.nonempty(product["current_title"] as? String)
            guard let title else { return nil }
            return ComponentStatus(
                name: title,
                severity: mapped.severity,
                statusText: mapped.text,
                id: JSONScalar.nonempty(product["id"] as? String) ?? title
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

    private static func pageName(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host == "status.firebase.google.com" { return "Firebase" }
        if host == "www.google.com" || host == "google.com" { return "Google Workspace" }
        return "Google Cloud"
    }
}
