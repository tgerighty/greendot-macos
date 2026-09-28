import AppKit
import StatusCore
import XCTest
@testable import greendot

@MainActor
final class ManagedPageMenuTests: XCTestCase {
    func testDisabledManagedPageHasEnableAction() {
        let page = WatchedPage(url: Self.pageURL, name: "Managed optional", required: false)
        var enabled: [UUID] = []
        let menu = MenuBuilderTests.managedMenu(disabledManagedPages: [page]) { enabled.append($0) }

        XCTAssertTrue(MenuCommands.perform(path: "Optional Managed Pages/Enable Managed optional", in: menu))
        XCTAssertEqual(enabled, [page.id])
    }

    func testManagedPageDoesNotOfferUnpersistedNotificationToggle() {
        let page = WatchedPage(url: Self.pageURL, name: "Managed", required: false)
        let menu = MenuBuilderTests.managedMenu(pages: [page])

        XCTAssertNil(menu.item(withTitle: "Managed")?.submenu?.item(withTitle: "Notifications"))
    }

    func testLocalPageOffersNotificationToggle() {
        let page = WatchedPage(url: Self.pageURL, name: "Local")
        let menu = MenuBuilderTests.managedMenu(pages: [page], disabledManagedPages: [])

        XCTAssertNotNil(menu.item(withTitle: "Local")?.submenu?.item(withTitle: "Notifications"))
    }

    private static let pageURL = URL(string: "https://managed-page.test")!

}
