public enum ComponentTree {
    public static func find(_ key: String, in items: [ComponentStatus]) -> ComponentStatus? {
        for item in items {
            if item.id == key || item.name == key { return item }
            if let hit = find(key, in: item.children) { return hit }
        }
        return nil
    }

    public static func collect(_ item: ComponentStatus) -> [ComponentStatus] {
        [item] + item.children.flatMap(collect)
    }

    public static func componentKeys(_ items: [ComponentStatus]) -> [String] {
        items.flatMap { item in
            [item.id, item.name] + componentKeys(item.children)
        }
    }
}
