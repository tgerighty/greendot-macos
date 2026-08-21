import AppKit

enum MenuCommands {
    @discardableResult
    static func perform(path: String, in menu: NSMenu) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return false }
        if parts.count == 1 {
            return invokeFirst(named: parts[0], in: menu)
        }
        return invoke(parts, in: menu)
    }

    static func dump(_ menu: NSMenu) -> String {
        var lines: [String] = []
        walk(menu, depth: 0, lines: &lines)
        return lines.joined(separator: "\n")
    }

    private static func invokeFirst(named title: String, in menu: NSMenu) -> Bool {
        for item in menu.items {
            if item.title == title { return invoke(item) }
            if let sub = item.submenu, invokeFirst(named: title, in: sub) { return true }
        }
        return false
    }

    private static func invoke(_ parts: [String], in menu: NSMenu) -> Bool {
        guard let first = parts.first else { return false }
        for item in menu.items where item.title == first {
            if parts.count == 1 { return invoke(item) }
            if let sub = item.submenu {
                return invoke(Array(parts.dropFirst()), in: sub)
            }
            return false
        }
        return false
    }

    private static func invoke(_ item: NSMenuItem) -> Bool {
        guard let box = item.representedObject as AnyObject? else { return false }
        _ = box.perform(NSSelectorFromString("invoke"))
        return true
    }

    private static func walk(_ menu: NSMenu, depth: Int, lines: inout [String]) {
        for item in menu.items {
            if item.isSeparatorItem { continue }
            lines.append(String(repeating: "  ", count: depth) + labeled(item))
            if let sub = item.submenu {
                walk(sub, depth: depth + 1, lines: &lines)
            }
        }
    }

    private static func labeled(_ item: NSMenuItem) -> String {
        let raw = item.identifier?.rawValue ?? ""
        guard raw.hasPrefix("notify-") || raw == "launch-at-login" else {
            return item.title
        }
        return item.title + (item.state == .on ? " [on]" : " [off]")
    }
}
