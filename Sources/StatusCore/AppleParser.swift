import Foundation

public enum AppleParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let services = json["services"] as? [[String: Any]] else {
            throw ParserError.notThisProvider
        }
        let components = services.compactMap(serviceGroup)
        return PageSnapshot(
            name: "Apple",
            url: ProviderProbe.normalizedBase(sourceURL),
            provider: .apple,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func serviceGroup(_ item: [String: Any]) -> ComponentStatus? {
        guard let name = JSONScalar.nonempty(item["serviceName"] as? String) else { return nil }
        let events = (item["events"] as? [[String: Any]] ?? []).compactMap { event -> ComponentStatus? in
            let status = (event["eventStatus"] as? String ?? event["dateStatus"] as? String ?? "").lowercased()
            if status == "resolved" || status == "completed" { return nil }
            let type = event["statusType"] as? String
            let mapped = StatusMapping.appleStatusType(type)
            let eventName = JSONScalar.nonempty(event["message"] as? String)
                ?? JSONScalar.nonempty(type)
                ?? "Issue"
            let firstLine = eventName.split(whereSeparator: \.isNewline).first.map(String.init) ?? eventName
            return ComponentStatus(
                name: firstLine,
                severity: mapped.severity,
                statusText: mapped.text,
                id: firstLine
            )
        }
        guard !events.isEmpty else { return nil }
        let worst = ComponentTree.enabledLeafSeverity(in: events, disabledKeys: [])
        return ComponentStatus(
            name: name,
            severity: worst,
            statusText: events[0].statusText,
            id: name,
            children: events,
            isGroup: true
        )
    }
}
