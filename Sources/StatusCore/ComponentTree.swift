public enum ComponentTree {
    public static func find(_ key: String, in items: [ComponentStatus]) -> ComponentStatus? {
        for item in items {
            if item.id == key || item.name == key { return item }
            if let hit = find(key, in: item.children) { return hit }
        }
        return nil
    }

    public static func collect(_ item: ComponentStatus) -> [ComponentStatus] {
        var result: [ComponentStatus] = []
        append(item, to: &result)
        return result
    }

    public static func componentKeys(_ items: [ComponentStatus]) -> [String] {
        var result: [String] = []
        for item in items {
            appendKeys(item, to: &result)
        }
        return result
    }

    static func enabledLeafSeverity(
        in items: [ComponentStatus],
        disabledKeys: Set<String>,
        enabledRegions: [String]? = nil,
        ancestorAllowed: Bool = false
    ) -> Severity {
        enabledLeafSeverityIfPresent(
            in: items,
            disabledKeys: disabledKeys,
            enabledRegions: enabledRegions,
            ancestorAllowed: ancestorAllowed
        ) ?? .green
    }

    private static func enabledLeafSeverityIfPresent(
        in items: [ComponentStatus],
        disabledKeys: Set<String>,
        enabledRegions: [String]?,
        ancestorAllowed: Bool
    ) -> Severity? {
        var result: Severity?
        for item in items {
            let allowed = RegionFilter.allows(
                item,
                regions: enabledRegions,
                ancestorAllowed: ancestorAllowed
            )
            guard allowed,
                  !disabledKeys.contains(item.id),
                  !disabledKeys.contains(item.name) else { continue }
            let childSeverity = enabledLeafSeverityIfPresent(
                in: item.children,
                disabledKeys: disabledKeys,
                enabledRegions: enabledRegions,
                ancestorAllowed: enabledRegions != nil
            )
            let severity: Severity
            if item.isGroup, !item.children.isEmpty {
                severity = childSeverity ?? .green
            } else {
                severity = childSeverity ?? item.severity
            }
            result = moreSevere(result, severity)
            if result == .red { return .red }
        }
        return result
    }

    private static func moreSevere(_ current: Severity?, _ candidate: Severity) -> Severity {
        guard let current else { return candidate }
        return Aggregator.fromSeverities([current, candidate])
    }

    private static func append(_ item: ComponentStatus, to result: inout [ComponentStatus]) {
        result.append(item)
        for child in item.children {
            append(child, to: &result)
        }
    }

    private static func appendKeys(_ item: ComponentStatus, to result: inout [String]) {
        result.append(item.id)
        result.append(item.name)
        for child in item.children {
            appendKeys(child, to: &result)
        }
    }
}

public enum RegionFilter {
    /// `nil` regions means there is no region filter. An empty list matches nothing.
    public static func allows(
        _ component: ComponentStatus,
        regions: [String]?,
        ancestorAllowed: Bool
    ) -> Bool {
        guard let regions else { return true }
        if ancestorAllowed { return true }
        return matches(component, regions: regions)
    }

    public static func matches(_ component: ComponentStatus, regions: [String]) -> Bool {
        let name = component.name
        let id = component.id
        return regions.contains { token in
            guard !token.isEmpty else { return false }
            return name.range(of: token, options: .caseInsensitive) != nil
                || id.range(of: token, options: .caseInsensitive) != nil
        }
    }

    public static func allowedIDs(in components: [ComponentStatus], regions: [String]) -> Set<String> {
        var ids: Set<String> = []
        func walk(_ items: [ComponentStatus], ancestorAllowed: Bool) {
            for item in items {
                let allowed = allows(item, regions: regions, ancestorAllowed: ancestorAllowed)
                if allowed {
                    ids.insert(item.id)
                    ids.insert(item.name)
                }
                walk(item.children, ancestorAllowed: allowed)
            }
        }
        walk(components, ancestorAllowed: false)
        return ids
    }
}
