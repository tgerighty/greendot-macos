import Foundation

enum DirectStatus {
    static func snapshot(
        name: String,
        url: URL,
        provider: StatusProvider,
        components: [ComponentStatus]
    ) -> PageSnapshot {
        PageSnapshot(
            name: name,
            url: url,
            provider: provider,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }
}

public enum ConcurParser {
    public static func serviceGroup(data: Data, datacenter: String) throws -> ComponentStatus {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let services = json["data"] as? [String: Any] else {
            throw ParserError.notThisProvider
        }
        let children = services.keys.sorted().compactMap { key -> ComponentStatus? in
            guard let body = services[key] as? [String: Any] else { return nil }
            let current = body["Current Status"] as? [String: Any]
            let raw = JSONScalar.nonempty(current?["status"] as? String) ?? "normal"
            let mapped = map(raw)
            let name = JSONScalar.nonempty(body["Service"] as? String) ?? key
            return ComponentStatus(
                name: name,
                severity: mapped.0,
                statusText: mapped.1,
                id: datacenter + "|" + key
            )
        }
        return ComponentStatus(
            name: label(datacenter),
            severity: .green,
            statusText: "Operational",
            id: datacenter,
            children: children,
            isGroup: true
        )
    }

    static func label(_ datacenter: String) -> String {
        switch datacenter {
        case "us": return "US"
        case "us2": return "US2"
        case "eu2": return "EU2"
        case "apj1": return "APJ1"
        case "usg": return "US Government"
        default: return datacenter.uppercased()
        }
    }

    private static func map(_ status: String) -> (Severity, String) {
        switch status.lowercased() {
        case "normal", "operational":
            return (.green, "Operational")
        case "disruption", "outage":
            return (.red, "Disruption")
        case "degradation", "degraded":
            return (.yellow, "Degradation")
        default:
            return (.yellow, status)
        }
    }
}

public enum AdobeParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["incidentEvent"] as? [String: Any],
              let incidents = event["incidents"] as? [String: Any] else {
            throw ParserError.notThisProvider
        }
        var byID: [String: ComponentStatus] = [:]
        for incident in incidents.values {
            guard let incident = incident as? [String: Any],
                  let products = incident["products"] as? [String: Any] else { continue }
            let catalog = ServiceCatalog(incident["services"])
            let watched = watchedProductIDs(incident["clouds"])
            for (key, value) in products {
                guard watched.contains(key) || watched.contains(productID(value, key: key)),
                      let product = value as? [String: Any],
                      let component = openProduct(product, key: key, catalog: catalog) else { continue }
                if let existing = byID[component.id] {
                    byID[component.id] = merge(existing, component)
                } else {
                    byID[component.id] = component
                }
            }
        }
        let components = byID.values.sorted { $0.name < $1.name }
        return DirectStatus.snapshot(
            name: "Adobe",
            url: sourceURL,
            provider: .adobe,
            components: components
        )
    }

    private static let watchedCloudNames: Set<String> = ["document cloud", "creative cloud"]

    private static func watchedProductIDs(_ value: Any?) -> Set<String> {
        guard let clouds = value as? [String: Any] else { return [] }
        var ids: Set<String> = []
        for cloudValue in clouds.values {
            guard let cloud = cloudValue as? [String: Any],
                  let name = JSONScalar.nonempty(cloud["name"] as? String)?.lowercased(),
                  watchedCloudNames.contains(name),
                  let products = cloud["cloudProducts"] as? [Any] else { continue }
            for product in products {
                if let id = JSONScalar.stringID(product) {
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    private static func productID(_ value: Any, key: String) -> String {
        guard let product = value as? [String: Any] else { return key }
        return JSONScalar.nonempty(product["id"] as? String) ?? JSONScalar.stringID(product["id"]) ?? key
    }

    private static func openProduct(
        _ product: [String: Any],
        key: String,
        catalog: ServiceCatalog
    ) -> ComponentStatus? {
        guard let latest = latestHistory(product["history"]),
              let status = JSONScalar.nonempty(latest["status"] as? String)?.lowercased(),
              status != "closed", status != "dismissed" else { return nil }
        let name = JSONScalar.nonempty(product["name"] as? String) ?? key
        let mapped = severity(latest["severity"] as? String)
        let id = JSONScalar.nonempty(product["id"] as? String) ?? JSONScalar.stringID(product["id"]) ?? key
        let children = serviceChildren(
            ids: impactedServiceIDs(latest["serviceImpact"]),
            productID: id,
            mapped: mapped,
            catalog: catalog
        )
        return ComponentStatus(
            name: name,
            severity: mapped.0,
            statusText: mapped.1,
            id: id,
            children: children,
            isGroup: !children.isEmpty
        )
    }

    private static func serviceChildren(
        ids: [String],
        productID: String,
        mapped: (Severity, String),
        catalog: ServiceCatalog
    ) -> [ComponentStatus] {
        var seen: Set<String> = []
        var children: [ComponentStatus] = []
        for serviceID in ids {
            guard seen.insert(serviceID).inserted,
                  let serviceName = catalog.names[serviceID] else { continue }
            children.append(ComponentStatus(
                name: serviceName,
                severity: mapped.0,
                statusText: mapped.1,
                id: productID + "|" + serviceID
            ))
        }
        return children.sorted { $0.name < $1.name }
    }

    private static func impactedServiceIDs(_ value: Any?) -> [String] {
        guard let impact = value as? [String: Any],
              let services = impact["productServices"] as? [Any] else { return [] }
        return services.compactMap { JSONScalar.stringID($0) }
    }

    private static func merge(_ lhs: ComponentStatus, _ rhs: ComponentStatus) -> ComponentStatus {
        let severity = Aggregator.fromSeverities([lhs.severity, rhs.severity])
        let statusText = lhs.severity == severity ? lhs.statusText : rhs.statusText
        var childrenByID: [String: ComponentStatus] = [:]
        for child in lhs.children + rhs.children {
            if let existing = childrenByID[child.id] {
                childrenByID[child.id] = merge(existing, child)
            } else {
                childrenByID[child.id] = child
            }
        }
        let children = childrenByID.values.sorted { $0.name < $1.name }
        return ComponentStatus(
            name: lhs.name,
            severity: severity,
            statusText: statusText,
            id: lhs.id,
            children: children,
            isGroup: !children.isEmpty
        )
    }

    private struct ServiceCatalog {
        let names: [String: String]

        init(_ value: Any?) {
            var names: [String: String] = [:]
            if let services = value as? [String: Any] {
                for (key, value) in services {
                    guard let service = value as? [String: Any] else { continue }
                    let name = JSONScalar.nonempty(service["name"] as? String) ?? key
                    names[key] = name
                    if let id = JSONScalar.stringID(service["id"]) {
                        names[id] = name
                    }
                }
            }
            self.names = names
        }
    }

    private static func latestHistory(_ value: Any?) -> [String: Any]? {
        guard let history = value as? [String: Any], !history.isEmpty else { return nil }
        let key = history.keys.max { (Int($0) ?? 0) < (Int($1) ?? 0) }
        return key.flatMap { history[$0] as? [String: Any] }
    }

    private static func severity(_ raw: String?) -> (Severity, String) {
        switch raw?.lowercased() {
        case "major", "critical", "high":
            return (.red, "Major")
        default:
            return (.yellow, raw ?? "Degraded")
        }
    }
}

public enum AzureDevOpsParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let services = json["services"] as? [[String: Any]] else {
            throw ParserError.notThisProvider
        }
        let components = services.compactMap(service)
        let top = health(status["health"] as? String)
        var all = components
        if components.isEmpty {
            all = [ComponentStatus(name: "Azure DevOps", severity: top.0, statusText: top.1, id: "overall")]
        }
        return DirectStatus.snapshot(
            name: "Azure DevOps",
            url: sourceURL,
            provider: .azuredevops,
            components: all
        )
    }

    private static func service(_ item: [String: Any]) -> ComponentStatus? {
        guard let name = JSONScalar.nonempty(item["id"] as? String) else { return nil }
        let geos = (item["geographies"] as? [[String: Any]] ?? []).compactMap { geo -> ComponentStatus? in
            guard let geoName = JSONScalar.nonempty(geo["name"] as? String) else { return nil }
            let mapped = health(geo["health"] as? String)
            let id = JSONScalar.nonempty(geo["id"] as? String) ?? geoName
            return ComponentStatus(
                name: geoName,
                severity: mapped.0,
                statusText: mapped.1,
                id: name + "|" + id
            )
        }
        return ComponentStatus(
            name: name,
            severity: .green,
            statusText: "Operational",
            id: name,
            children: geos,
            isGroup: true
        )
    }

    private static func health(_ raw: String?) -> (Severity, String) {
        switch raw?.lowercased() {
        case "healthy", "ok", "operational":
            return (.green, "Operational")
        case "unhealthy", "down", "critical", "incident":
            return (.red, "Major outage")
        case "degraded", "warning", "advisory":
            return (.yellow, "Degraded")
        default:
            return (.yellow, raw ?? "Degraded")
        }
    }
}

public enum N8nParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let monitors = json["data"] as? [[String: Any]] else {
            throw ParserError.notThisProvider
        }
        let components = monitors.compactMap { monitor -> ComponentStatus? in
            guard let name = JSONScalar.nonempty(monitor["name"] as? String) else { return nil }
            let mapped = map(monitor["statusClass"] as? String)
            let id = JSONScalar.stringID(monitor["monitorId"]) ?? name
            return ComponentStatus(name: name, severity: mapped.0, statusText: mapped.1, id: id)
        }
        return DirectStatus.snapshot(name: "n8n", url: sourceURL, provider: .n8n, components: components)
    }

    private static func map(_ statusClass: String?) -> (Severity, String) {
        switch statusClass?.lowercased() {
        case "success":
            return (.green, "Operational")
        case "danger":
            return (.red, "Down")
        case "warning":
            return (.yellow, "Degraded")
        default:
            return (.yellow, statusClass ?? "Degraded")
        }
    }
}

public enum ZscalerParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["data"] as? [String: Any],
              let severity = JSONScalar.nonempty(body["severity"] as? String) else {
            throw ParserError.notThisProvider
        }
        let mapped = map(severity)
        let title = JSONScalar.nonempty(body["title"] as? String) ?? "Zscaler"
        let components = mapped.0 == .green
            ? []
            : [ComponentStatus(name: title, severity: mapped.0, statusText: mapped.1, id: "banner")]
        return DirectStatus.snapshot(
            name: "Zscaler",
            url: sourceURL,
            provider: .zscaler,
            components: components
        )
    }

    private static func map(_ severity: String) -> (Severity, String) {
        switch severity.lowercased() {
        case "none", "normal", "operational", "ok":
            return (.green, "Operational")
        case "disruption", "outage", "critical", "major", "down":
            return (.red, "Disruption")
        default:
            return (.yellow, "Degraded")
        }
    }
}
