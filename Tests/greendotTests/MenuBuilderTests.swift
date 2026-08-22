import AppKit
import StatusCore
import XCTest
@testable import greendot

final class MenuBuilderTests: XCTestCase {
    func testPageRowOpensPageURL() {
        var opened: [URL] = []
        let page = Self.nestedPage()
        let menu = Self.menu(page: page, onOpen: { opened.append($0) })
        let item = menu.item(withTitle: "Box")
        XCTAssertNotNil(item?.representedObject, "page row should open the status URL")
        Self.invoke(item)
        XCTAssertEqual(opened, [Self.pageURL])
    }

    func testLeafComponentOpensPageURL() {
        var opened: [URL] = []
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { opened.append($0) })
        let leaf = Self.findItem("Content API    Operational", in: menu)
        XCTAssertNotNil(leaf?.action)
        Self.invoke(leaf)
        XCTAssertEqual(opened, [Self.pageURL])
    }

    func testGroupRowOpensPageURL() {
        var opened: [URL] = []
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { opened.append($0) })
        let group = Self.findItem("Box Web Application", in: menu)
        XCTAssertNotNil(group?.representedObject, "group row should open the status URL")
        Self.invoke(group)
        XCTAssertEqual(opened, [Self.pageURL])
    }

    func testOpenStatusPageOpensPageURL() {
        var opened: [URL] = []
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { opened.append($0) })
        let item = Self.findItem("Open Status Page", in: menu)
        XCTAssertNotNil(item?.action)
        Self.invoke(item)
        XCTAssertEqual(opened, [Self.pageURL])
    }

    func testMenuHasAboutGreendotImmediatelyAboveQuit() {
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { _ in })
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("About greendot"), titles.joined(separator: " | "))
        let about = titles.firstIndex(of: "About greendot")
        let quit = titles.firstIndex(of: "Quit greendot")
        XCTAssertEqual(about.map { $0 + 1 }, quit)
    }

    func testAboutInvokesCallback() {
        var aboutCount = 0
        let menu = MenuBuilder.build(
            pages: [],
            launchAtLoginEnabled: false,
            actions: MenuActions(
                onAdd: {},
                onEdit: { _ in },
                onRemove: { _ in },
                onToggleNotifications: { _ in },
                onOpen: { _ in },
                onRefresh: {},
                onToggleLaunchAtLogin: {},
                onAbout: { aboutCount += 1 },
                onQuit: {}
            )
        )
        Self.invoke(menu.item(withTitle: "About greendot"))
        XCTAssertEqual(aboutCount, 1)
    }

    func testPerformPathOpensNestedEditAndLeaf() {
        var edited: [String] = []
        var opened: [URL] = []
        let menu = MenuBuilder.build(
            pages: [Self.nestedPage()],
            launchAtLoginEnabled: false,
            actions: MenuActions(
                onAdd: {},
                onEdit: { edited.append($0.name) },
                onRemove: { _ in },
                onToggleNotifications: { _ in },
                onOpen: { opened.append($0) },
                onRefresh: {},
                onToggleLaunchAtLogin: {},
                onAbout: {},
                onQuit: {}
            )
        )
        XCTAssertTrue(MenuCommands.perform(path: "Box/Edit…", in: menu))
        XCTAssertEqual(edited, ["Box"])
        XCTAssertTrue(MenuCommands.perform(path: "API    Operational", in: menu) == false)
        XCTAssertTrue(MenuCommands.perform(path: "Content API    Operational", in: menu))
        XCTAssertEqual(opened, [Self.pageURL])
        let dump = MenuCommands.dump(menu)
        XCTAssertTrue(dump.contains("Box Web Application"))
        XCTAssertTrue(dump.contains("Open Status Page"))
    }

    private static let pageURL = URL(string: "https://status.box.com")!

    private static func menu(page: WatchedPage, onOpen: @escaping (URL) -> Void) -> NSMenu {
        MenuBuilder.build(
            pages: [page],
            launchAtLoginEnabled: false,
            actions: MenuActions(
                onAdd: {},
                onEdit: { _ in },
                onRemove: { _ in },
                onToggleNotifications: { _ in },
                onOpen: onOpen,
                onRefresh: {},
                onToggleLaunchAtLogin: {},
                onAbout: {},
                onQuit: {}
            )
        )
    }

    private static func invoke(_ item: NSMenuItem?) {
        guard let item, let target = item.representedObject as AnyObject? else { return }
        _ = target.perform(NSSelectorFromString("invoke"))
    }

    private static func findItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let sub = item.submenu, let hit = findItem(title, in: sub) { return hit }
        }
        return nil
    }

    private static func nestedPage() -> WatchedPage {
        let group = ComponentStatus(
            name: "Box Web Application",
            severity: .green,
            statusText: "Operational",
            id: "g1",
            children: [
                ComponentStatus(name: "Login/SSO", severity: .green, statusText: "Operational", id: "c1"),
                ComponentStatus(name: "Search", severity: .green, statusText: "Operational", id: "c2")
            ],
            isGroup: true
        )
        let leaf = ComponentStatus(name: "Content API", severity: .green, statusText: "Operational", id: "c3")
        return WatchedPage(
            url: pageURL,
            name: "Box",
            snapshot: PageSnapshot(
                name: "Box",
                url: pageURL,
                provider: .statuspage,
                overall: .green,
                components: [group, leaf],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}
