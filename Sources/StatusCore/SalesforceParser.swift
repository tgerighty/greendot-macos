import Foundation

public enum SalesforceParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let items = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ParserError.notThisProvider
        }
        let components = items.compactMap { item -> ComponentStatus? in
            guard let incident = item as? [String: Any] else { return nil }
            return incidentGroup(incident)
        }
        return PageSnapshot(
            name: "Salesforce",
            url: sourceURL,
            provider: .salesforce,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func incidentGroup(_ incident: [String: Any]) -> ComponentStatus? {
        guard let id = intID(incident["id"]) else { return nil }
        if (incident["status"] as? String)?.lowercased() == "resolved" { return nil }
        let mapped = StatusMapping.salesforce(incident["type"] as? String)
        return ComponentStatus(
            name: incidentName(incident, id: id),
            severity: mapped.severity,
            statusText: mapped.text,
            id: id,
            children: serviceChildren(incident["serviceKeys"], mapped: mapped),
            isGroup: true
        )
    }

    private static func incidentName(_ incident: [String: Any], id: String) -> String {
        if let extra = incident["additionalInformation"] as? String {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
            }
        }
        let type = JSONScalar.nonempty(incident["type"] as? String)
        let external = JSONScalar.nonempty(incident["externalId"] as? String)
        if let type, let external { return "\(type) \(external)" }
        if let type { return "\(type) \(id)" }
        return external ?? id
    }

    private static func serviceChildren(
        _ raw: Any?,
        mapped: (severity: Severity, text: String)
    ) -> [ComponentStatus] {
        (raw as? [String] ?? []).compactMap { key in
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return ComponentStatus(
                name: name,
                severity: mapped.severity,
                statusText: mapped.text,
                id: name
            )
        }
    }

    private static func intID(_ value: Any?) -> String? {
        if let number = value as? Int { return String(number) }
        if let number = value as? NSNumber { return number.stringValue }
        if let text = JSONScalar.nonempty(value as? String), text.allSatisfy(\.isNumber) { return text }
        return nil
    }

}
