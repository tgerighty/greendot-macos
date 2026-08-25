import AppKit
import StatusCore

final class StatusMenuController: NSObject {
    private let statusItem: NSStatusItem
    private let clickOpener: MenuClickOpener
    private let builder: MenuBuilder
    private let activateApplication: () -> Void
    private let presentMenu: (NSMenu) -> Void
    private let scheduleOnMain: (@escaping () -> Void) -> Void
    private var state: StatusMenuState
    private var needsReload = false
    private var needsPop = false
    private var displayedSeverity: Severity?

    init(
        state: StatusMenuState,
        handlers: StatusMenuHandlers,
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        clickOpener: MenuClickOpener = MenuClickOpener(),
        activateApplication: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) },
        presentMenu: @escaping (NSMenu) -> Void = StatusMenuController.presentAtScreenCenter,
        scheduleOnMain: @escaping (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.async(execute: work)
        }
    ) {
        self.state = state
        self.statusItem = statusItem
        self.clickOpener = clickOpener
        builder = MenuBuilder(handlers: handlers)
        self.activateApplication = activateApplication
        self.presentMenu = presentMenu
        self.scheduleOnMain = scheduleOnMain
        super.init()
        configureStatusItem()
        clickOpener.onTrackingEnded = { [weak self] in
            self?.scheduleDeferredMenuWork()
        }
        updateSeverity(state.severity)
        applyMenu()
    }

    func update(_ state: StatusMenuState) {
        let menuContentChanged = self.state.pages != state.pages
            || self.state.launchAtLoginEnabled != state.launchAtLoginEnabled
        self.state = state
        updateSeverity(state.severity)
        guard menuContentChanged else { return }
        if clickOpener.isTracking {
            needsReload = true
            return
        }
        needsReload = false
        applyMenu()
    }

    /// UI tests use this when a menu-bar manager parks the NSStatusItem off-screen.
    func popMenuOnScreen() {
        activateApplication()
        if clickOpener.isTracking {
            needsPop = true
            return
        }
        needsPop = false
        needsReload = false
        presentPopMenu()
    }

    @discardableResult
    func performMenuPath(_ path: String) -> Bool {
        MenuCommands.perform(path: path, in: statusItem.menu ?? NSMenu())
    }

    func dumpMenu() -> String {
        MenuCommands.dump(statusItem.menu ?? NSMenu())
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "greendot"
        statusItem.button?.setAccessibilityLabel("greendot")
        statusItem.menu = NSMenu()
    }

    private func updateSeverity(_ severity: Severity) {
        guard displayedSeverity != severity else { return }
        displayedSeverity = severity
        statusItem.button?.image = StatusDot.image(severity, size: 14)
        statusItem.button?.toolTip = "greendot"
    }

    private func applyMenu() {
        let menu = builder.build(for: state)
        clickOpener.attach(menu)
        statusItem.menu = menu
    }

    private func presentPopMenu() {
        applyMenu()
        presentMenu(statusItem.menu ?? NSMenu())
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

    private func scheduleDeferredMenuWork() {
        scheduleOnMain { [weak self] in
            self?.flushDeferredMenuWork()
        }
    }

    private static func presentAtScreenCenter(_ menu: NSMenu) {
        let fallback = NSRect(x: 0, y: 0, width: 800, height: 600)
        let screen = NSScreen.main?.visibleFrame ?? fallback
        let point = NSPoint(x: screen.midX, y: screen.midY)
        menu.popUp(positioning: nil, at: point, in: nil)
    }
}
