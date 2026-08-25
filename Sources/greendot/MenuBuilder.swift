import AppKit
import StatusCore

struct StatusMenuState: Equatable {
    var pages: [WatchedPage]
    var severity: Severity
    var launchAtLoginEnabled: Bool
}

struct StatusMenuHandlers {
    var onAdd: () -> Void
    var onEdit: (UUID) -> Void
    var onRemove: (UUID) -> Void
    var onToggleNotifications: (UUID) -> Void
    var onOpen: (URL) -> Void
    var onRefresh: () -> Void
    var onToggleLaunchAtLogin: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
}

final class MenuBuilder {
    private struct Content: Equatable {
        var pages: [WatchedPage]
        var launchAtLoginEnabled: Bool
    }

    private let handlers: StatusMenuHandlers
    private var cachedContent: Content?
    private var cachedMenu: NSMenu?

    init(handlers: StatusMenuHandlers) {
        self.handlers = handlers
    }

    func build(for state: StatusMenuState) -> NSMenu {
        let content = Content(pages: state.pages, launchAtLoginEnabled: state.launchAtLoginEnabled)
        if cachedContent == content, let cachedMenu {
            return cachedMenu
        }
        let menu = NSMenu()
        menu.autoenablesItems = false

        if state.pages.isEmpty {
            let empty = NSMenuItem(title: "No status pages", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for page in state.pages {
                menu.addItem(pageItem(page))
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Add Status Page…", identifier: "add-page", action: handlers.onAdd))
        menu.addItem(actionItem("Refresh", identifier: "refresh", action: handlers.onRefresh))

        let login = actionItem(
            "Launch at Login",
            identifier: "launch-at-login",
            action: handlers.onToggleLaunchAtLogin
        )
        login.state = state.launchAtLoginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(actionItem("About greendot", identifier: "about", action: handlers.onAbout))
        menu.addItem(actionItem("Quit greendot", identifier: "quit", action: handlers.onQuit))
        cachedContent = content
        cachedMenu = menu
        return menu
    }

    private func pageItem(_ page: WatchedPage) -> NSMenuItem {
        let handlers = self.handlers
        let severity = page.displaySeverity
        let item = NSMenuItem(
            title: page.name,
            action: nil,
            keyEquivalent: ""
        )
        item.image = StatusDot.image(severity)
        item.identifier = NSUserInterfaceItemIdentifier("page-\(page.id.uuidString)")
        item.submenu = pageSubmenu(page)
        let url = page.snapshot?.url ?? page.url
        TargetAction.install(item) { handlers.onOpen(url) }
        return item
    }

    private func pageSubmenu(_ page: WatchedPage) -> NSMenu {
        let handlers = self.handlers
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
                menu.addItem(componentItem(component, url: url, onOpen: handlers.onOpen))
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

        addIncidents(snapshot?.incidents ?? [], pageURL: snapshot?.url, onOpen: handlers.onOpen, to: menu)
        menu.addItem(.separator())
        let notify = actionItem("Notifications", identifier: "notify-\(page.id.uuidString)") {
            handlers.onToggleNotifications(page.id)
        }
        notify.state = page.notificationsEnabled ? .on : .off
        menu.addItem(notify)
        menu.addItem(actionItem("Edit…", identifier: "edit-\(page.id.uuidString)") { handlers.onEdit(page.id) })
        menu.addItem(actionItem("Remove", identifier: "remove-\(page.id.uuidString)") {
            handlers.onRemove(page.id)
        })
        menu.addItem(actionItem("Open Status Page", identifier: "open-\(page.id.uuidString)") {
            handlers.onOpen(snapshot?.url ?? page.url)
        })
        return menu
    }

    private func addIncidents(
        _ incidents: [Incident],
        pageURL: URL?,
        onOpen: @escaping (URL) -> Void,
        to menu: NSMenu
    ) {
        guard !incidents.isEmpty else { return }
        menu.addItem(.separator())
        for incident in incidents {
            let row = NSMenuItem(title: incident.title, action: nil, keyEquivalent: "")
            if let url = incident.url ?? pageURL {
                TargetAction.install(row) { onOpen(url) }
            } else {
                row.isEnabled = false
            }
            menu.addItem(row)
        }
    }

    private func componentItem(
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
        }
        TargetAction.install(row) { onOpen(url) }
        return row
    }

    private func overallText(_ severity: Severity) -> String {
        switch severity {
        case .green: return "Operational"
        case .yellow: return "Degraded"
        case .red: return "Major outage"
        case .grey: return "Unreachable"
        }
    }

    private func actionItem(
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
final class TargetAction: NSObject {
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
