import AppKit

/// NSMenu ignores an item's action when that item has a submenu. This fires the
/// action on click so a page or group row still opens its URL.
final class MenuClickOpener: NSObject, NSMenuDelegate {
    private(set) var isTracking = false
    var onTrackingEnded: (() -> Void)?

    private var highlighted: NSMenuItem?
    private var monitor: Any?
    private var openCount = 0

    deinit {
        removeMonitor()
    }

    func attach(_ menu: NSMenu) {
        menu.delegate = self
        for item in menu.items {
            if let sub = item.submenu {
                attach(sub)
            }
        }
    }

    func menu(_: NSMenu, willHighlight item: NSMenuItem?) {
        highlighted = item
    }

    func menuWillOpen(_: NSMenu) {
        if openCount == 0 {
            isTracking = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.handleClick(event) ?? event
            }
        }
        openCount += 1
    }

    func menuDidClose(_: NSMenu) {
        openCount = max(openCount - 1, 0)
        if openCount == 0 {
            highlighted = nil
            isTracking = false
            removeMonitor()
            onTrackingEnded?()
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleClick(_ event: NSEvent) -> NSEvent? {
        guard let item = highlighted, item.submenu != nil else { return event }
        guard let box = item.representedObject as? TargetAction else { return event }
        guard clickIsOnMenuRow(event) else { return event }
        box.invoke()
        item.menu?.cancelTracking()
        return nil
    }

    /// Do not steal clicks from titled windows (Add/Edit). Menu popups are not titled.
    private func clickIsOnMenuRow(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return true }
        if window.styleMask.contains(.titled) { return false }
        return true
    }
}
