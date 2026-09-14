import Foundation

public enum OktaParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        guard let incidentJSON = embeddedJSON(named: "incidents", in: html) else {
            throw ParserError.notThisProvider
        }
        let incidents = array(incidentJSON)
        let outages = embeddedJSON(named: "planned-outages", in: html).map(array) ?? []
        let active = incidents.compactMap(incidentGroup)
        let planned = outages.compactMap(outageGroup)
        let components = active + planned
        return PageSnapshot(
            name: "Okta",
            url: ProviderProbe.normalizedBase(sourceURL),
            provider: .okta,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func incidentGroup(_ object: [String: Any]) -> ComponentStatus? {
        let status = (object["Status__c"] as? String ?? "").lowercased()
        if status == "resolved" { return nil }
        guard let id = object["Id"] as? String, !id.isEmpty else { return nil }
        let name = (object["Incident_Title__c"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (object["Name"] as? String)
            ?? id
        let mapped = StatusMapping.oktaCategory(object["Category__c"] as? String)
        let children = cells(object["Impacted_Cells__c"]).map { cell in
            ComponentStatus(
                name: cell,
                severity: mapped.severity,
                statusText: mapped.text,
                id: cell
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

    private static func outageGroup(_ object: [String: Any]) -> ComponentStatus? {
        guard let id = object["Id"] as? String, !id.isEmpty else { return nil }
        let name = (object["OutageDetails__c"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Planned outage"
        return ComponentStatus(
            name: name,
            severity: .yellow,
            statusText: "Maintenance",
            id: id,
            isGroup: true
        )
    }

    private static func cells(_ raw: Any?) -> [String] {
        guard let text = raw as? String else { return [] }
        return text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func array(_ data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private static func embeddedJSON(named id: String, in html: String) -> Data? {
        guard let idRange = html.range(of: "data-id=\"\(id)\"") else { return nil }
        guard let open = html[idRange.upperBound...].firstIndex(of: ">") else { return nil }
        let start = html.index(after: open)
        guard let close = html[start...].range(of: "</span>") else { return nil }
        let json = html[start..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard json.hasPrefix("[") || json.hasPrefix("{") else { return nil }
        return Data(json.utf8)
    }
}
