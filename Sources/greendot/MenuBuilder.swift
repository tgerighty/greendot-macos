import AppKit
import StatusCore

enum MenuBuilder {
    static func build(
        pages: [WatchedPage],
        barSeverity: Severity,
        onAdd: @escaping () -> Void,
        onEdit: @escaping (WatchedPage) -> Void,
        onRemove: @escaping (UUID) -> Void,
        onToggleNotifications: @escaping (UUID) -> Void,
        onOpen: @escaping (URL) -> Void,
        onRefresh: @escaping () -> Void,
        launchAtLoginEnabled: Bool,
        onToggleLaunchAtLogin: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if pages.isEmpty {
            let empty = NSMenuItem(title: "No status pages", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for page in pages {
                menu.addItem(pageItem(page, onEdit: onEdit, onRemove: onRemove,
                                      onToggleNotifications: onToggleNotifications, onOpen: onOpen))
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Add Status Page…", identifier: "add-page", action: onAdd))
        menu.addItem(actionItem("Refresh", identifier: "refresh", action: onRefresh))

        let login = actionItem("Launch at Login", identifier: "launch-at-login", action: onToggleLaunchAtLogin)
        login.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit greendot", identifier: "quit", action: onQuit))
        _ = barSeverity
        return menu
    }

    private static func pageItem(
        _ page: WatchedPage,
        onEdit: @escaping (WatchedPage) -> Void,
        onRemove: @escaping (UUID) -> Void,
        onToggleNotifications: @escaping (UUID) -> Void,
        onOpen: @escaping (URL) -> Void
    ) -> NSMenuItem {
        let severity = page.displaySeverity
        let item = NSMenuItem(
            title: page.name,
            action: nil,
            keyEquivalent: ""
        )
        item.image = StatusDot.image(severity)
        item.identifier = NSUserInterfaceItemIdentifier("page-\(page.id.uuidString)")
        item.submenu = pageSubmenu(
            page,
            onEdit: onEdit,
            onRemove: onRemove,
            onToggleNotifications: onToggleNotifications,
            onOpen: onOpen
        )
        return item
    }

    private static func pageSubmenu(
        _ page: WatchedPage,
        onEdit: @escaping (WatchedPage) -> Void,
        onRemove: @escaping (UUID) -> Void,
        onToggleNotifications: @escaping (UUID) -> Void,
        onOpen: @escaping (URL) -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let snapshot = page.snapshot

        if snapshot?.isUnreachable == true {
            let row = NSMenuItem(title: "Unreachable", action: nil, keyEquivalent: "")
            row.isEnabled = false
            row.image = StatusDot.image(.grey)
            menu.addItem(row)
        }

        let components = page.enabledComponents
        if !components.isEmpty {
            let url = snapshot?.url ?? page.url
            for component in components {
                menu.addItem(componentItem(component, url: url, onOpen: onOpen))
            }
        } else if snapshot?.isUnreachable != true {
            let row = NSMenuItem(
                title: overallText(page.displaySeverity),
                action: nil,
                keyEquivalent: ""
            )
            row.isEnabled = false
            row.image = StatusDot.image(page.displaySeverity)
            menu.addItem(row)
        }

        if let incidents = snapshot?.incidents, !incidents.isEmpty {
            menu.addItem(.separator())
            for incident in incidents {
                let row = NSMenuItem(title: incident.title, action: nil, keyEquivalent: "")
                if let url = incident.url ?? snapshot?.url {
                    TargetAction.install(row) { onOpen(url) }
                } else {
                    row.isEnabled = false
                }
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())
        let notify = actionItem("Notifications", identifier: "notify-\(page.id.uuidString)") {
            onToggleNotifications(page.id)
        }
        notify.state = page.notificationsEnabled ? .on : .off
        menu.addItem(notify)
        menu.addItem(actionItem("Edit…", identifier: "edit-\(page.id.uuidString)") { onEdit(page) })
        menu.addItem(actionItem("Remove", identifier: "remove-\(page.id.uuidString)") { onRemove(page.id) })
        menu.addItem(actionItem("Open Status Page", identifier: "open-\(page.id.uuidString)") {
            onOpen(snapshot?.url ?? page.url)
        })
        return menu
    }

    private static func componentItem(
        _ component: ComponentStatus,
        url: URL,
        onOpen: @escaping (URL) -> Void
    ) -> NSMenuItem {
        let title = component.isGroup || !component.children.isEmpty
            ? component.name
            : "\(component.name)    \(component.statusText)"
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.image = StatusDot.image(component.severity)
        row.identifier = NSUserInterfaceItemIdentifier(component.id)
        if !component.children.isEmpty {
            let sub = NSMenu()
            sub.autoenablesItems = false
            for child in component.children {
                sub.addItem(componentItem(child, url: url, onOpen: onOpen))
            }
            row.submenu = sub
        } else {
            TargetAction.install(row) { onOpen(url) }
        }
        return row
    }

    private static func overallText(_ severity: Severity) -> String {
        switch severity {
        case .green: return "Operational"
        case .yellow: return "Degraded"
        case .red: return "Major outage"
        case .grey: return "Unreachable"
        }
    }

    private static func actionItem(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(identifier)
        TargetAction.install(item, action)
        return item
    }
}

/// Keeps a closure alive as the menu item target. NSMenuItem retains its target.
private final class TargetAction: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }

    static func install(_ item: NSMenuItem, _ action: @escaping () -> Void) {
        let box = TargetAction(action)
        item.target = box
        item.action = #selector(TargetAction.invoke)
        item.representedObject = box
    }
}
