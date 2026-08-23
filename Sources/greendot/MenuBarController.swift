import AppKit
import StatusCore

final class MenuBarController: NSObject {
    var menuProvider: (() -> NSMenu)?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let clickOpener = MenuClickOpener()
    private var needsReload = false
    private var needsPop = false
    private var displayedSeverity: Severity?

    override init() {
        super.init()
        statusItem.button?.image = StatusDot.image(.green, size: 14)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "greendot"
        statusItem.button?.setAccessibilityLabel("greendot")
        statusItem.menu = NSMenu()
        clickOpener.onTrackingEnded = { [weak self] in
            self?.flushDeferredMenuWork()
        }
    }

    func setSeverity(_ severity: Severity) {
        if displayedSeverity == severity { return }
        displayedSeverity = severity
        statusItem.button?.image = StatusDot.image(severity, size: 14)
        statusItem.button?.toolTip = "greendot"
    }

    func reloadMenu() {
        if clickOpener.isTracking {
            needsReload = true
            return
        }
        applyMenu()
    }

    /// UI tests use this when a menu-bar manager parks the NSStatusItem off-screen.
    func popMenuOnScreen() {
        NSApp.activate(ignoringOtherApps: true)
        if clickOpener.isTracking {
            needsPop = true
            return
        }
        presentPopMenu()
    }

    @discardableResult
    func performMenuPath(_ path: String) -> Bool {
        MenuCommands.perform(path: path, in: menuProvider?() ?? NSMenu())
    }

    func dumpMenu() -> String {
        MenuCommands.dump(menuProvider?() ?? NSMenu())
    }

    private func applyMenu() {
        let menu = menuProvider?() ?? NSMenu()
        clickOpener.attach(menu)
        statusItem.menu = menu
    }

    private func presentPopMenu() {
        applyMenu()
        let menu = statusItem.menu ?? NSMenu()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let point = NSPoint(x: screen.midX, y: screen.midY)
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    private func flushDeferredMenuWork() {
        if needsPop {
            needsPop = false
            needsReload = false
            presentPopMenu()
            return
        }
        if needsReload {
            needsReload = false
            applyMenu()
        }
    }
}
