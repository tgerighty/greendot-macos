import Foundation

public enum AwsParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let events = try JSONSerialization.jsonObject(with: utf8JSONBytes(data)) as? [Any] else {
            throw ParserError.notThisProvider
        }
        let components = events.compactMap { item -> ComponentStatus? in
            guard let event = item as? [String: Any] else { return nil }
            return eventGroup(event)
        }
        return PageSnapshot(
            name: "AWS",
            url: sourceURL,
            provider: .aws,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func eventGroup(_ event: [String: Any]) -> ComponentStatus? {
        guard let arn = event["arn"] as? String, !arn.isEmpty else { return nil }
        let serviceName = (event["service_name"] as? String) ?? ""
        let regionName = (event["region_name"] as? String) ?? ""
        let name = regionName.isEmpty ? serviceName : "\(serviceName) (\(regionName))"
        let raw = rawStatus(event["status"])
        return ComponentStatus(
            name: name,
            severity: StatusMapping.aws(raw),
            statusText: StatusMapping.awsText(raw),
            id: arn,
            children: impactedChildren(event["impacted_services"]),
            isGroup: true
        )
    }

    private static func impactedChildren(_ raw: Any?) -> [ComponentStatus] {
        guard let map = raw as? [String: Any] else { return [] }
        return map.compactMap { key, value in
            guard let child = value as? [String: Any] else { return nil }
            guard let name = child["service_name"] as? String, !name.isEmpty else { return nil }
            let current = rawStatus(child["current"])
            return ComponentStatus(
                name: name,
                severity: StatusMapping.aws(current),
                statusText: StatusMapping.awsText(current),
                id: key
            )
        }
        .sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }

    private static func rawStatus(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func utf8JSONBytes(_ data: Data) -> Data {
        guard let text = utf16JSONString(data), let utf8 = text.data(using: .utf8) else {
            return data
        }
        return utf8
    }

    private static func utf16JSONString(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(2))
        let encoding: String.Encoding
        if bytes[0] == 0xFE, bytes[1] == 0xFF {
            encoding = .utf16
        } else if bytes[0] == 0xFF, bytes[1] == 0xFE {
            encoding = .utf16
        } else if bytes[0] == 0, bytes[1] == 0x5B {
            encoding = .utf16BigEndian
        } else if bytes[0] == 0x5B, bytes[1] == 0 {
            encoding = .utf16LittleEndian
        } else {
            return nil
        }
        return String(data: data, encoding: encoding)
    }
}
