import AppKit
import StatusCore

@MainActor
enum StatusDot {
    private struct Key: Hashable {
        var severity: Severity
        var size: CGFloat
    }

    private static let lock = NSLock()
    private static var cache: [Key: NSImage] = [:]

    static func image(_ severity: Severity, size: CGFloat = 12) -> NSImage {
        let key = Key(severity: severity, size: size)
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color(severity).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: rect.width - 2, height: rect.height - 2)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = severity.rawValue
        cache[key] = image
        return image
    }

    static func color(_ severity: Severity) -> NSColor {
        switch severity {
        case .green: return NSColor.systemGreen
        case .yellow: return NSColor.systemYellow
        case .red: return NSColor.systemRed
        case .grey: return NSColor.systemGray
        }
    }
}
