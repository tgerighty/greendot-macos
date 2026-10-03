import AppKit
import StatusCore

/// Colours from the greendot.cloud public page (`src/html/styles.ts`).
/// Dark chrome uses the same hues at a lower lightness. Status green, yellow, and red stay put.
enum GreendotStyle {
    struct Palette {
        var background: NSColor
        var foreground: NSColor
        var card: NSColor
        var muted: NSColor
        var line: NSColor
    }

    static let windowMarker = NSUserInterfaceItemIdentifier("greendot.chrome")
    static var choice: InterfaceStyle = .system

    static let radius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let good = srgb(0, 0.5552, 0.1964)
    static let warn = srgb(0.8174, 0.5641, 0.1161)
    static let bad = srgb(0.7869, 0.1840, 0.1989)

    static let lightPalette = Palette(
        background: srgb(0.9362, 0.9753, 0.9920),
        foreground: srgb(0.0543, 0.1197, 0.1736),
        card: NSColor.white,
        muted: srgb(0.2493, 0.3101, 0.3634),
        line: srgb(0.8134, 0.8842, 0.9142)
    )
    static let darkPalette = Palette(
        background: srgb(0.0307, 0.0734, 0.1095),
        foreground: srgb(0.8570, 0.9218, 0.9493),
        card: srgb(0.0644, 0.1192, 0.1652),
        muted: srgb(0.5981, 0.6559, 0.6858),
        line: srgb(0.1774, 0.2255, 0.2676)
    )

    static let background = dynamic("greendot.background") { palette(matching: $0).background }
    static let foreground = dynamic("greendot.foreground") { palette(matching: $0).foreground }
    static let card = dynamic("greendot.card") { palette(matching: $0).card }
    static let muted = dynamic("greendot.muted") { palette(matching: $0).muted }
    static let line = dynamic("greendot.line") { palette(matching: $0).line }

    static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    static var usesDarkChrome: Bool {
        switch choice {
        case .dark: return true
        case .light: return false
        case .system: return systemIsDark
        }
    }

    static func palette(matching appearance: NSAppearance) -> Palette {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? darkPalette : lightPalette
    }

    static func concrete(_ severity: Severity, darkChrome: Bool) -> NSColor {
        switch severity {
        case .green: return good
        case .yellow: return warn
        case .red: return bad
        case .grey: return darkChrome ? darkPalette.muted : lightPalette.muted
        }
    }

    static func appearance(for style: InterfaceStyle) -> NSAppearance? {
        switch style {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Pins the window when the user chose Light or Dark. `nil` lets the window follow the Mac.
    static func applyAppearance(_ window: NSWindow) {
        window.identifier = windowMarker
        window.appearance = appearance(for: choice)
    }

    static func paint(_ window: NSWindow) {
        applyAppearance(window)
        window.backgroundColor = background
    }

    static func refreshOpenWindows() {
        for window in NSApp.windows where window.identifier == windowMarker {
            window.appearance = appearance(for: choice)
        }
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

    static func applyCardChrome(_ view: NSView) {
        let colors = palette(matching: view.effectiveAppearance)
        view.layer?.backgroundColor = colors.card.cgColor
        view.layer?.borderColor = colors.line.cgColor
    }

    private static func dynamic(_ name: String, _ resolve: @escaping (NSAppearance) -> NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name), dynamicProvider: resolve)
    }

    private static func srgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

/// Card with a 1 px line and 12 pt corners. The colours follow the window appearance.
final class StyledScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        wantsLayer = true
        layer?.cornerRadius = GreendotStyle.radius
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    private func applyChrome() {
        let colors = GreendotStyle.palette(matching: effectiveAppearance)
        backgroundColor = colors.card
        GreendotStyle.applyCardChrome(self)
    }
}
