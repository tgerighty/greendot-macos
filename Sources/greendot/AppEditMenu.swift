import AppKit

/// Accessory apps have no Edit menu, so Cmd+C / Cmd+V never reach a text field.
@MainActor
enum AppEditMenu {
    static func install() {
        NSApp.mainMenu = makeMainMenu()
    }

    static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let about = NSMenuItem(title: "About greendot", action: nil, keyEquivalent: "")
        TargetAction.install(about) { AboutPanel.show() }
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide greendot",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "Quit greendot",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return main
    }
}
