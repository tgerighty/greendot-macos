import AppKit
import StatusCore

struct StatusMenuState: Equatable {
    struct Content: Equatable {
        let pages: [WatchedPage]
        let disabledManagedPages: [WatchedPage]
        let launchAtLoginEnabled: Bool
    }

    var pages: [WatchedPage]
    var disabledManagedPages: [WatchedPage] = []
    var severity: Severity
    var launchAtLoginEnabled: Bool

    /// Values that affect the built menu. Severity only affects the status-item image.
    var content: Content {
        Content(pages: pages, disabledManagedPages: disabledManagedPages, launchAtLoginEnabled: launchAtLoginEnabled)
    }
}

struct StatusMenuHandlers {
    var onAdd: () -> Void
    var onEdit: (UUID) -> Void
    var onRemove: (UUID) -> Void
    var onToggleNotifications: (UUID) -> Void
    var onEnableManagedPage: (UUID) -> Void = { _ in }
    var onOpen: (URL) -> Void
    var onRefresh: () -> Void
    var onRevealConfig: () -> Void
    var onReloadConfig: () -> Void
    var onToggleLaunchAtLogin: () -> Void
    var onAbout: () -> Void
    var onQuit: () -> Void
}

@MainActor
final class MenuBuilder {
    private let handlers: StatusMenuHandlers
    private var cachedContent: StatusMenuState.Content?
    private var cachedMenu: NSMenu?

    init(handlers: StatusMenuHandlers) {
        self.handlers = handlers
    }

    func build(for state: StatusMenuState) -> NSMenu {
        let content = state.content
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

        if !state.disabledManagedPages.isEmpty {
            let parent = NSMenuItem(title: "Optional Managed Pages", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for page in state.disabledManagedPages {
                submenu.addItem(actionItem("Enable \(page.name)", identifier: "enable-managed-\(page.id.uuidString)") {
                    self.handlers.onEnableManagedPage(page.id)
                })
            }
            parent.submenu = submenu
            menu.addItem(parent)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Add Status Page…", identifier: "add-page", action: handlers.onAdd))
        menu.addItem(actionItem("Refresh", identifier: "refresh", action: handlers.onRefresh))
        menu.addItem(
            actionItem("Reveal Config File", identifier: "reveal-config", action: handlers.onRevealConfig)
        )
        menu.addItem(actionItem("Reload Config", identifier: "reload-config", action: handlers.onReloadConfig))

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
                title: page.displaySeverity.displayName,
                action: nil,
                keyEquivalent: ""
            )
            row.image = StatusDot.image(page.displaySeverity)
            let url = snapshot?.url ?? page.url
            TargetAction.install(row) { handlers.onOpen(url) }
            menu.addItem(row)
        }

        addIncidents(snapshot?.incidents ?? [], pageURL: snapshot?.url, onOpen: handlers.onOpen, to: menu)
        menu.addItem(.separator())
        if page.required == nil {
            let notify = actionItem("Notifications", identifier: "notify-\(page.id.uuidString)") {
                handlers.onToggleNotifications(page.id)
            }
            notify.state = page.notificationsEnabled ? .on : .off
            menu.addItem(notify)
            menu.addItem(actionItem("Edit…", identifier: "edit-\(page.id.uuidString)") { handlers.onEdit(page.id) })
        }
        if page.required != true {
            let action = page.required == false ? "Disable" : "Remove"
            let identifier = "remove-\(page.id.uuidString)"
            menu.addItem(actionItem(action, identifier: identifier) {
                handlers.onRemove(page.id)
            })
        }
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
