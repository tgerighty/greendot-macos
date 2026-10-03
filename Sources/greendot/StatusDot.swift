import AppKit
import StatusCore

@MainActor
enum StatusDot {
    private struct Key: Hashable {
        var severity: Severity
        var size: CGFloat
    }

    private static var cache: [Key: NSImage] = [:]

    static func image(_ severity: Severity, size: CGFloat = 12) -> NSImage {
        let key = Key(severity: severity, size: size)
        if let hit = cache[key] { return hit }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fill = color(severity)
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

    static func color(_ severity: Severity) -> NSColor {
        GreendotStyle.color(severity)
    }
}
