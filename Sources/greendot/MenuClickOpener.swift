import AppKit

/// NSMenu ignores an item's action when that item has a submenu. This fires the
/// action on click so a page or group row still opens its URL.
final class MenuClickOpener: NSObject, NSMenuDelegate {
    private var highlighted: NSMenuItem?
    private var monitor: Any?
    private var openCount = 0

    static func install(_ menu: NSMenu) {
        let opener = MenuClickOpener()
        attach(menu, opener)
    }

    private static func attach(_ menu: NSMenu, _ opener: MenuClickOpener) {
        menu.delegate = opener
        objc_setAssociatedObject(menu, &associateKey, opener, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        for item in menu.items {
            if let sub = item.submenu {
                attach(sub, opener)
            }
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlighted = item
        _ = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if openCount == 0 {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleClick(event) ?? event
            }
        }
        openCount += 1
        _ = menu
    }

    func menuDidClose(_ menu: NSMenu) {
        openCount = max(openCount - 1, 0)
        if openCount == 0, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
            highlighted = nil
        }
        _ = menu
    }

    private func handleClick(_ event: NSEvent) -> NSEvent? {
        guard let item = highlighted, item.submenu != nil else { return event }
        guard let box = item.representedObject as AnyObject? else { return event }
        _ = box.perform(NSSelectorFromString("invoke"))
        item.menu?.cancelTracking()
        return nil
    }
}

private var associateKey: UInt8 = 0
