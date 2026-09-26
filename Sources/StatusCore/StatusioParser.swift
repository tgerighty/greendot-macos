import Foundation

public enum StatusioParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let overall = result["status_overall"] as? [String: Any] else {
            throw ParserError.notThisProvider
        }
        let mapped = StatusMapping.statusio(JSONScalar.intValue(overall["status_code"]))
        let components = (result["status"] as? [[String: Any]] ?? []).compactMap(component)
        let leaves = ComponentTree.enabledLeafSeverity(in: components, disabledKeys: [])
        let overallSeverity = Aggregator.fromSeverities([mapped.severity, leaves])
        return PageSnapshot(
            name: sourceURL.host ?? "Status page",
            url: sourceURL,
            provider: .statusio,
            overall: overallSeverity,
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func component(_ item: [String: Any]) -> ComponentStatus? {
        guard let name = JSONScalar.nonempty(item["name"] as? String) else { return nil }
        let mapped = StatusMapping.statusio(JSONScalar.intValue(item["status_code"]))
        let children = (item["containers"] as? [[String: Any]] ?? []).compactMap { child -> ComponentStatus? in
            guard let childName = JSONScalar.nonempty(child["name"] as? String) else { return nil }
            let childMapped = StatusMapping.statusio(JSONScalar.intValue(child["status_code"]))
            return ComponentStatus(
                name: childName,
                severity: childMapped.severity,
                statusText: childMapped.text,
                id: JSONScalar.stringID(child["id"]) ?? childName
            )
        }
        return ComponentStatus(
            name: name,
            severity: mapped.severity,
            statusText: mapped.text,
            id: JSONScalar.stringID(item["id"]) ?? name,
            children: children,
            isGroup: true
        )
    }
}

enum JSONScalar {
    static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    static func stringID(_ value: Any?) -> String? {
        if let text = nonempty(value as? String) { return text }
        if let number = intValue(value) { return String(number) }
        return nil
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
