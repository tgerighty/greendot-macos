import AppKit
import StatusCore

enum StatusDot {
    static func image(_ severity: Severity, size: CGFloat = 12) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color(severity).setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2)).fill()
        image.unlockFocus()
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
