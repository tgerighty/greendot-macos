import AppKit
import StatusCore
import XCTest
@testable import greendot

@MainActor
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
        var scheduledWork: ScheduledMainActorWork?
        var editedIDs: [UUID] = []
        let firstPage = Self.page(name: "First")
        let controller = StatusMenuController(
            state: Self.state(page: firstPage, severity: .green),
            handlers: Self.handlers(onEdit: { editedIDs.append($0) }),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: {
                XCTFail("Updating a tracked menu must not activate the application")
            },
            presentMenu: { _ in
                XCTFail("Updating a tracked menu must not present it")
            },
            scheduleOnMain: { work in scheduledWork = work }
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
        try XCTUnwrap(scheduledWork)()

        XCTAssertFalse(statusItem.menu === firstMenu)
        XCTAssertTrue(controller.dumpMenu().contains("Latest"))
        XCTAssertFalse(controller.dumpMenu().contains("Second"))
    }

    func testDeferredPopUsesLatestStateAndSupersedesReload() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let tracking = MenuClickOpener()
        var scheduledWork: ScheduledMainActorWork?
        var presentedMenus: [NSMenu] = []
        var activationCount = 0
        let controller = StatusMenuController(
            state: Self.state(page: Self.page(name: "First")),
            handlers: Self.handlers(),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: { activationCount += 1 },
            presentMenu: { presentedMenus.append($0) },
            scheduleOnMain: { work in scheduledWork = work }
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
        XCTAssertTrue(presentedMenus.isEmpty)
        try XCTUnwrap(scheduledWork)()

        XCTAssertEqual(presentedMenus.count, 1)
        XCTAssertTrue(presentedMenus.first === statusItem.menu)
        XCTAssertTrue(controller.dumpMenu().contains("Latest"))
    }

    func testDeferredPopPresentationWaitsUntilNextMainRunLoopTurnAfterTrackingEnds() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let tracking = MenuClickOpener()
        var activationCount = 0
        var presentedMenus: [NSMenu] = []
        let didPresent = expectation(description: "deferred menu presentation")
        let controller = StatusMenuController(
            state: Self.state(page: Self.page(name: "Tracked")),
            handlers: Self.handlers(),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: { activationCount += 1 },
            presentMenu: { menu in
                presentedMenus.append(menu)
                didPresent.fulfill()
            }
        )
        let trackedMenu = try XCTUnwrap(statusItem.menu)

        tracking.menuWillOpen(trackedMenu)
        controller.popMenuOnScreen()
        XCTAssertEqual(activationCount, 1)

        tracking.menuDidClose(trackedMenu)

        XCTAssertTrue(presentedMenus.isEmpty)
        wait(for: [didPresent], timeout: 1)
        XCTAssertEqual(presentedMenus.count, 1)
    }

    func testDeferredPopWaitsWhenTrackingRestartsBeforeScheduledFlush() throws {
        _ = NSApplication.shared
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let tracking = MenuClickOpener()
        var scheduledWork: [ScheduledMainActorWork] = []
        var presentedMenus: [NSMenu] = []
        var activationCount = 0
        let controller = StatusMenuController(
            state: Self.state(page: Self.page(name: "Tracked")),
            handlers: Self.handlers(),
            statusItem: statusItem,
            clickOpener: tracking,
            activateApplication: { activationCount += 1 },
            presentMenu: { presentedMenus.append($0) },
            scheduleOnMain: { scheduledWork.append($0) }
        )
        let trackedMenu = try XCTUnwrap(statusItem.menu)

        tracking.menuWillOpen(trackedMenu)
        controller.update(Self.state(page: Self.page(name: "Latest")))
        controller.popMenuOnScreen()
        tracking.menuDidClose(trackedMenu)
        tracking.menuWillOpen(trackedMenu)

        try XCTUnwrap(scheduledWork.first)()
        scheduledWork.removeFirst()

        XCTAssertTrue(presentedMenus.isEmpty)
        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(statusItem.menu === trackedMenu)

        tracking.menuDidClose(trackedMenu)
        try XCTUnwrap(scheduledWork.first)()

        XCTAssertEqual(presentedMenus.count, 1)
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

    private static func handlers(
        onEdit: @escaping (UUID) -> Void = { _ in XCTFail("Unexpected edit action") }
    ) -> StatusMenuHandlers {
        StatusMenuHandlers(
            onAdd: { XCTFail("Unexpected add action") },
            onEdit: onEdit,
            onRemove: { _ in XCTFail("Unexpected remove action") },
            onToggleNotifications: { _ in XCTFail("Unexpected notification action") },
            onOpen: { _ in XCTFail("Unexpected open action") },
            onRefresh: { XCTFail("Unexpected refresh action") },
            onToggleLaunchAtLogin: { XCTFail("Unexpected launch-at-login action") },
            onAbout: { XCTFail("Unexpected about action") },
            onQuit: { XCTFail("Unexpected quit action") }
        )
    }
}
