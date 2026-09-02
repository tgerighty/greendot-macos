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
        disabledKeys: Set<String>
    ) -> Severity {
        enabledLeafSeverityIfPresent(in: items, disabledKeys: disabledKeys) ?? .green
    }

    private static func enabledLeafSeverityIfPresent(
        in items: [ComponentStatus],
        disabledKeys: Set<String>
    ) -> Severity? {
        var result: Severity?
        for item in items {
            guard !disabledKeys.contains(item.id),
                  !disabledKeys.contains(item.name) else { continue }
            let childSeverity = enabledLeafSeverityIfPresent(
                in: item.children,
                disabledKeys: disabledKeys
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
        if current == .red || candidate == .red { return .red }
        if current == .yellow || candidate == .yellow { return .yellow }
        if current == .green || candidate == .green { return .green }
        return .grey
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
