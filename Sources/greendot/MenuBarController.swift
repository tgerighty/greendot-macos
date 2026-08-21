import AppKit
import StatusCore

final class MenuBarController: NSObject {
    var menuProvider: (() -> NSMenu)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    override init() {
        super.init()
        statusItem.button?.image = StatusDot.image(.green, size: 14)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "greendot"
        statusItem.button?.setAccessibilityLabel("greendot")
        statusItem.menu = NSMenu()
    }

    func setSeverity(_ severity: Severity) {
        statusItem.button?.image = StatusDot.image(severity, size: 14)
        statusItem.button?.toolTip = "greendot"
    }

    func reloadMenu() {
        statusItem.menu = menuProvider?() ?? NSMenu()
    }

    /// UI tests use this when a menu-bar manager parks the extra off-screen.
    func popMenuOnScreen() {
        NSApp.activate(ignoringOtherApps: true)
        let menu = menuProvider?() ?? NSMenu()
        statusItem.menu = menu
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let point = NSPoint(x: screen.midX, y: screen.maxY - 8)
        menu.popUp(positioning: nil, at: point, in: nil)
    }
}
