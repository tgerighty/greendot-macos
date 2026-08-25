import AppKit
import StatusCore
import XCTest
@testable import greendot

final class StatusMenuControllerTests: XCTestCase {
    func testSeverityOnlyUpdateReusesMenuAndUpdatesIcon() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let page = Self.page(name: "Page")
        let controller = StatusMenuController(
            state: Self.state(page: page, severity: .green),
            handlers: Self.handlers(),
            statusItem: statusItem
        )
        let firstMenu = try XCTUnwrap(statusItem.menu)

        controller.update(Self.state(page: page, severity: .red))

        XCTAssertTrue(statusItem.menu === firstMenu)
        XCTAssertEqual(statusItem.button?.image?.accessibilityDescription, Severity.red.rawValue)
    }

    func testLaunchAtLoginChangeRebuildsMenu() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let page = Self.page(name: "Page")
        let controller = StatusMenuController(
            state: Self.state(page: page),
            handlers: Self.handlers(),
            statusItem: statusItem
        )
        let firstMenu = try XCTUnwrap(statusItem.menu)
        XCTAssertEqual(firstMenu.item(withTitle: "Launch at Login")?.state, .off)

        controller.update(Self.state(page: page, launchAtLoginEnabled: true))

        let updatedMenu = try XCTUnwrap(statusItem.menu)
        XCTAssertFalse(updatedMenu === firstMenu)
        XCTAssertEqual(updatedMenu.item(withTitle: "Launch at Login")?.state, .on)
    }

    func testUpdatesIconImmediatelyButDefersLatestMenuUntilTrackingEnds() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let tracking = MenuClickOpener()
        var editedIDs: [UUID] = []
        let firstPage = Self.page(name: "First")
        let controller = StatusMenuController(
            state: Self.state(page: firstPage, severity: .green),
            handlers: Self.handlers(onEdit: { editedIDs.append($0) }),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: {},
            presentMenu: { _ in }
        )
        let firstMenu = try XCTUnwrap(statusItem.menu)

        tracking.menuWillOpen(firstMenu)
        let secondPage = Self.page(name: "Second")
        controller.update(Self.state(page: secondPage, severity: .yellow))
        let latestPage = Self.page(name: "Latest")
        controller.update(Self.state(page: latestPage, severity: .red))

        XCTAssertTrue(statusItem.menu === firstMenu)
        XCTAssertEqual(statusItem.button?.image?.accessibilityDescription, Severity.red.rawValue)
        XCTAssertTrue(controller.dumpMenu().contains("First"))
        XCTAssertFalse(controller.dumpMenu().contains("Latest"))
        XCTAssertTrue(controller.performMenuPath("First/Edit…"))
        XCTAssertEqual(editedIDs, [firstPage.id])

        tracking.menuDidClose(firstMenu)

        XCTAssertFalse(statusItem.menu === firstMenu)
        XCTAssertTrue(controller.dumpMenu().contains("Latest"))
        XCTAssertFalse(controller.dumpMenu().contains("Second"))
    }

    func testDeferredPopUsesLatestStateAndSupersedesReload() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let tracking = MenuClickOpener()
        var presentedMenus: [NSMenu] = []
        var activationCount = 0
        let controller = StatusMenuController(
            state: Self.state(page: Self.page(name: "First")),
            handlers: Self.handlers(),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: { activationCount += 1 },
            presentMenu: { presentedMenus.append($0) }
        )
        let trackedMenu = try XCTUnwrap(statusItem.menu)

        tracking.menuWillOpen(trackedMenu)
        controller.update(Self.state(page: Self.page(name: "Second")))
        controller.popMenuOnScreen()
        controller.update(Self.state(page: Self.page(name: "Latest")))

        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(presentedMenus.isEmpty)
        XCTAssertTrue(statusItem.menu === trackedMenu)

        tracking.menuDidClose(trackedMenu)

        XCTAssertEqual(presentedMenus.count, 1)
        XCTAssertTrue(presentedMenus.first === statusItem.menu)
        XCTAssertTrue(controller.dumpMenu().contains("Latest"))
    }

    func testControllersOwnIndependentMenusAndStableHandlers() throws {
        _ = NSApplication.shared
        let firstStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let secondStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(firstStatusItem)
            NSStatusBar.system.removeStatusItem(secondStatusItem)
        }
        let page = Self.page(name: "Shared State")
        var firstEdits: [UUID] = []
        var secondEdits: [UUID] = []
        let first = StatusMenuController(
            state: Self.state(page: page),
            handlers: Self.handlers(onEdit: { firstEdits.append($0) }),
            statusItem: firstStatusItem
        )
        let second = StatusMenuController(
            state: Self.state(page: page),
            handlers: Self.handlers(onEdit: { secondEdits.append($0) }),
            statusItem: secondStatusItem
        )

        XCTAssertFalse(firstStatusItem.menu === secondStatusItem.menu)
        XCTAssertTrue(first.performMenuPath("Shared State/Edit…"))
        XCTAssertTrue(second.performMenuPath("Shared State/Edit…"))
        XCTAssertEqual(firstEdits, [page.id])
        XCTAssertEqual(secondEdits, [page.id])
    }

    private static func state(
        page: WatchedPage,
        severity: Severity = .green,
        launchAtLoginEnabled: Bool = false
    ) -> StatusMenuState {
        StatusMenuState(
            pages: [page],
            severity: severity,
            launchAtLoginEnabled: launchAtLoginEnabled
        )
    }

    private static func page(name: String) -> WatchedPage {
        WatchedPage(url: URL(string: "https://status.example")!, name: name)
    }

    private static func handlers(onEdit: @escaping (UUID) -> Void = { _ in }) -> StatusMenuHandlers {
        StatusMenuHandlers(
            onAdd: {},
            onEdit: onEdit,
            onRemove: { _ in },
            onToggleNotifications: { _ in },
            onOpen: { _ in },
            onRefresh: {},
            onToggleLaunchAtLogin: {},
            onAbout: {},
            onQuit: {}
        )
    }
}
