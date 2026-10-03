import AppKit
import StatusCore

/// Colours from the greendot.cloud public page (`src/html/styles.ts`).
enum GreendotStyle {
    static let background = srgb(0.9362, 0.9753, 0.9920)
    static let foreground = srgb(0.0543, 0.1197, 0.1736)
    static let card = NSColor.white
    static let muted = srgb(0.2493, 0.3101, 0.3634)
    static let line = srgb(0.8134, 0.8842, 0.9142)
    static let good = srgb(0, 0.5552, 0.1964)
    static let warn = srgb(0.8174, 0.5641, 0.1161)
    static let bad = srgb(0.7869, 0.1840, 0.1989)
    static let radius: CGFloat = 12
    static let controlRadius: CGFloat = 8

    static func color(_ severity: Severity) -> NSColor {
        switch severity {
        case .green: return good
        case .yellow: return warn
        case .red: return bad
        case .grey: return muted
        }
    }

    static func paint(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = background
    }

    static func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = muted
        return label
    }

    static func primary(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = good.cgColor
        button.layer?.cornerRadius = controlRadius
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
            ]
        )
    }

    private static func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
