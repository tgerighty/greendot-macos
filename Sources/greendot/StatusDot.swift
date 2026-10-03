import AppKit
import StatusCore

@MainActor
enum StatusDot {
    private struct Key: Hashable {
        var severity: Severity
        var size: CGFloat
        var darkChrome: Bool
    }

    private static var cache: [Key: NSImage] = [:]

    /// `darkChrome` nil uses the menu bar appearance. A toast passes the panel appearance.
    static func image(_ severity: Severity, size: CGFloat = 12, darkChrome: Bool? = nil) -> NSImage {
        let dark = darkChrome ?? GreendotStyle.systemIsDark
        let key = Key(severity: severity, size: size, darkChrome: dark)
        if let hit = cache[key] { return hit }
        let fill = GreendotStyle.concrete(severity, darkChrome: dark)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            fill.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: rect).fill()
            // The cloud dot is 0.7rem inside a 0.22rem ring. 1.14rem is the full mark.
            let scale = 0.7 / 1.14
            let inset = rect.width * (1 - scale) / 2
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = severity.rawValue
        cache[key] = image
        return image
    }

    static func clearCache() {
        cache.removeAll()
    }

    static func color(_ severity: Severity) -> NSColor {
        GreendotStyle.concrete(severity, darkChrome: GreendotStyle.usesDarkChrome)
    }
}
