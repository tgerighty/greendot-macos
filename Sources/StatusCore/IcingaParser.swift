import Foundation

public enum IcingaParser {
    public static func parse(hosts: Data, services: Data, sourceURL: URL) throws -> PageSnapshot {
        let hostObjects = try objects(hosts)
        let serviceObjects = try objects(services)
        var groups: [String: HostGroup] = [:]
        for object in hostObjects {
            guard let host = hostRecord(object) else { continue }
            groups[host.id] = host
        }
        for object in serviceObjects {
            guard let service = serviceRecord(object) else { continue }
            var group = groups[service.hostID] ?? HostGroup(
                id: service.hostID,
                name: service.hostID,
                state: 0,
                downtime: false
            )
            group.services.append(service)
            groups[service.hostID] = group
        }
        let components = groups.values
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            .map(component)
        let clickURL = URLAuth.strippingUserinfo(sourceURL)
        return PageSnapshot(
            name: clickURL.host ?? "Icinga",
            url: clickURL,
            provider: .icinga,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func objects(_ data: Data) throws -> [[String: Any]] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [Any] else {
            throw ParserError.notThisProvider
        }
        return results.compactMap { $0 as? [String: Any] }
    }

    private static func component(_ host: HostGroup) -> ComponentStatus {
        let hostStatus = StatusMapping.icingaHost(host.state, downtime: host.downtime)
        let hostChild = ComponentStatus(
            name: "Host",
            severity: hostStatus.severity,
            statusText: hostStatus.text,
            id: "\(host.id)!__host"
        )
        let serviceChildren = host.services
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            .map { service -> ComponentStatus in
                let status = StatusMapping.icingaService(service.state, downtime: service.downtime)
                return ComponentStatus(
                    name: service.name,
                    severity: status.severity,
                    statusText: status.text,
                    id: service.id
                )
            }
        return ComponentStatus(
            name: host.name,
            severity: hostStatus.severity,
            statusText: hostStatus.text,
            id: host.id,
            children: [hostChild] + serviceChildren,
            isGroup: true
        )
    }

    private static func hostRecord(_ object: [String: Any]) -> HostGroup? {
        let attrs = object["attrs"] as? [String: Any] ?? [:]
        guard let id = string(attrs["name"]) ?? string(object["name"]), !id.isEmpty else { return nil }
        let name = string(attrs["display_name"]).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return HostGroup(
            id: id,
            name: name,
            state: intValue(attrs["state"]),
            downtime: isPositive(attrs["downtime_depth"])
        )
    }

    private static func serviceRecord(_ object: [String: Any]) -> ServiceRecord? {
        let attrs = object["attrs"] as? [String: Any] ?? [:]
        guard let hostID = string(attrs["host_name"]), !hostID.isEmpty else { return nil }
        let serviceName = string(attrs["name"]) ?? string(object["name"]) ?? ""
        guard !serviceName.isEmpty else { return nil }
        let name = string(attrs["display_name"]).flatMap { $0.isEmpty ? nil : $0 } ?? serviceName
        let id = string(attrs["__name"]).flatMap { $0.isEmpty ? nil : $0 } ?? "\(hostID)!\(serviceName)"
        return ServiceRecord(
            id: id,
            name: name,
            hostID: hostID,
            state: intValue(attrs["state"]),
            downtime: isPositive(attrs["downtime_depth"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return Int(exactly: number.doubleValue) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func isPositive(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.doubleValue > 0 }
        if let value = value as? Double { return value > 0 }
        if let value = value as? Int { return value > 0 }
        return false
    }

    private struct HostGroup {
        var id: String
        var name: String
        var state: Int?
        var downtime: Bool
        var services: [ServiceRecord] = []
    }

    private struct ServiceRecord {
        var id: String
        var name: String
        var hostID: String
        var state: Int?
        var downtime: Bool
    }
}
