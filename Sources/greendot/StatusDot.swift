import AppKit
import StatusCore

enum StatusDot {
    static func image(_ severity: Severity, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color(severity).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: rect.width - 2, height: rect.height - 2)).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = severity.rawValue
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
