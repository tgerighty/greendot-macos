import AppKit

enum UITestDriver {
    @discardableResult
    static func clickIdentifier(_ identifier: String) -> Bool {
        guard let button = findButton(identifier) else { return false }
        button.performClick(nil)
        return true
    }

    @discardableResult
    static func setField(_ identifier: String, value: String) -> Bool {
        guard let field = findField(identifier) else { return false }
        field.stringValue = value
        return true
    }

    @discardableResult
    static func focusField(_ identifier: String) -> Bool {
        guard let field = findField(identifier) else { return false }
        field.window?.makeKeyAndOrderFront(nil)
        field.window?.makeFirstResponder(field)
        return true
    }

    static func identifiers() -> [String] {
        var found: [String] = []
        for window in NSApp.windows {
            collect(from: window.contentView, into: &found)
        }
        return found
    }

    private static func findButton(_ identifier: String) -> NSButton? {
        find(identifier) as? NSButton
    }

    private static func findField(_ identifier: String) -> NSTextField? {
        find(identifier) as? NSTextField
    }

    private static func find(_ identifier: String) -> NSView? {
        for window in NSApp.windows {
            if let hit = find(identifier, in: window.contentView) { return hit }
        }
        return nil
    }

    private static func find(_ identifier: String, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == identifier { return view }
        if let scroll = view as? NSScrollView, let document = scroll.documentView {
            if let hit = find(identifier, in: document) { return hit }
        }
        for child in view.subviews {
            if let hit = find(identifier, in: child) { return hit }
        }
        return nil
    }

    private static func collect(from view: NSView?, into found: inout [String]) {
        guard let view else { return }
        let identifier = view.accessibilityIdentifier()
        if !identifier.isEmpty { found.append(identifier) }
        if let scroll = view as? NSScrollView {
            collect(from: scroll.documentView, into: &found)
        }
        for child in view.subviews {
            collect(from: child, into: &found)
        }
    }
}
