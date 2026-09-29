import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class MenuBuilderTests: XCTestCase {
    func testRepeatedBuildReusesMenuWhenPagesUnchanged() {
        let page = Self.nestedPage()
        let builder = MenuBuilder(handlers: Self.handlers(onOpen: { _ in
            XCTFail("Building a menu must not invoke its open handler")
        }))
        let first = builder.build(for: Self.state(page: page))
        let second = builder.build(for: Self.state(page: page))
        XCTAssertTrue(first === second)
        var page2 = page
        page2.name = "Other"
        let third = builder.build(for: Self.state(page: page2))
        XCTAssertFalse(first === third)
        XCTAssertEqual(first.item(at: 0)?.title, "Box")
        XCTAssertEqual(third.item(at: 0)?.title, "Other")
    }

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
        let menu = MenuBuilder(handlers: Self.handlers(onAbout: { aboutCount += 1 }))
            .build(for: Self.state(pages: []))
        Self.invoke(menu.item(withTitle: "About greendot"))
        XCTAssertEqual(aboutCount, 1)
    }

    @MainActor func testMenuFromPolledPagesKeepsTitlesActionsAndSeverities() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = AppConfig()
        config.pages = Self.mixedProviderPages()
        let store = PageStore(directory: dir)
        try store.save(config)
        let monitor = Monitor(store: store, client: Self.mixedProviderClient())
        try monitor.load()
        let toasts = try await monitor.pollAll()
        XCTAssertEqual(toasts.map(\.pageName), ["GitHub"])
        XCTAssertEqual(toasts.first?.body, "Degraded")

        var opened: [URL] = []
        let menu = MenuBuilder(handlers: Self.handlers(onOpen: { opened.append($0) }))
            .build(for: Self.state(pages: monitor.pages))
        XCTAssertEqual(menu.item(at: 0)?.title, "GitHub")
        XCTAssertEqual(menu.item(at: 1)?.title, "Instatus")
        XCTAssertEqual(menu.item(at: 2)?.title, "Acme")
        XCTAssertEqual(menu.item(at: 0)?.image?.accessibilityDescription, Severity.yellow.rawValue)
        XCTAssertEqual(menu.item(at: 1)?.image?.accessibilityDescription, Severity.green.rawValue)
        XCTAssertEqual(menu.item(at: 2)?.image?.accessibilityDescription, Severity.green.rawValue)
        XCTAssertNotNil(Self.findItem("API slow", in: menu))
        XCTAssertNotNil(Self.findItem("Open Status Page", in: menu))
        XCTAssertTrue(menu.items.map(\.title).contains("About greendot"))
        Self.invoke(menu.item(withTitle: "GitHub"))
        XCTAssertEqual(opened, [URL(string: "https://www.githubstatus.com")!])
    }

    func testPerformPathOpensNestedEditAndLeaf() {
        var edited: [UUID] = []
        var opened: [URL] = []
        let page = Self.nestedPage()
        let menu = MenuBuilder(handlers: Self.handlers(
            onEdit: { edited.append($0) }, onOpen: { opened.append($0) }
        )).build(for: Self.state(page: page))
        XCTAssertTrue(MenuCommands.perform(path: "Box/Edit…", in: menu))
        XCTAssertEqual(edited, [page.id])
        XCTAssertTrue(MenuCommands.perform(path: "API    Operational", in: menu) == false)
        XCTAssertTrue(MenuCommands.perform(path: "Content API    Operational", in: menu))
        XCTAssertEqual(opened, [Self.pageURL])
        let dump = MenuCommands.dump(menu)
        XCTAssertTrue(dump.contains("Box Web Application"))
        XCTAssertTrue(dump.contains("Open Status Page"))
    }

    private static let pageURL = URL(string: "https://status.box.com")!

    private static func menu(page: WatchedPage, onOpen: @escaping (URL) -> Void) -> NSMenu {
        MenuBuilder(handlers: handlers(onOpen: onOpen)).build(for: state(page: page))
    }

    static func state(pages: [WatchedPage], disabledManagedPages: [WatchedPage] = []) -> StatusMenuState {
        StatusMenuState(pages: pages, disabledManagedPages: disabledManagedPages,
                        severity: .green, launchAtLoginEnabled: false)
    }

    private static func state(page: WatchedPage) -> StatusMenuState {
        state(pages: [page])
    }

    private static func invoke(_ item: NSMenuItem?) {
        guard let target = item?.representedObject as? TargetAction else { return }
        target.invoke()
    }

    private static func findItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title { return item }
            if let sub = item.submenu, let hit = findItem(title, in: sub) { return hit }
        }
        return nil
    }

    private static func mixedProviderClient() -> MapHTTPClient {
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Data("""
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "minor"},
          "components": [{"name": "API", "status": "degraded_performance", "group": false}],
          "incidents": [{"name": "API slow"}]
        }
        """.utf8), 200)
        inner.byURL["https://instat.us/summary.json"] = (Data("""
        {
          "page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"},
          "components": [{"name": "API", "status": "OPERATIONAL"}]
        }
        """.utf8), 200)
        inner.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Data("""
        {
          "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
          "current_status_type": null,
          "services": [{"name": "API", "current_incident_type": null, "children": []}],
          "incidents": []
        }
        """.utf8), 200)
        return inner
    }

    private static func mixedProviderPages() -> [WatchedPage] {
        [
            BenchmarkFixtures.greenPage(
                host: "www.githubstatus.com", name: "GitHub", provider: .statuspage
            ),
            BenchmarkFixtures.greenPage(
                host: "instat.us", name: "Instatus", provider: .instatus
            ),
            BenchmarkFixtures.greenPage(
                host: "acme.statuspal.io", name: "Acme", provider: .statuspal
            )
        ]
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

/// Kept out of the class body to stay inside the SwiftLint `type_body_length` limit.
extension MenuBuilderTests {
    static func handlers(
        onEdit: ((UUID) -> Void)? = nil,
        onEnableManagedPage: ((UUID) -> Void)? = nil,
        onOpen: ((URL) -> Void)? = nil,
        onRevealConfig: (() -> Void)? = nil,
        onReloadConfig: (() -> Void)? = nil,
        onAbout: (() -> Void)? = nil
    ) -> StatusMenuHandlers {
        StatusMenuHandlers(
            onAdd: noOp,
            onEdit: onEdit ?? ignore,
            onRemove: ignore,
            onToggleNotifications: ignore,
            onEnableManagedPage: onEnableManagedPage ?? ignore,
            onOpen: onOpen ?? ignore,
            onRefresh: noOp,
            onRevealConfig: onRevealConfig ?? noOp,
            onReloadConfig: onReloadConfig ?? noOp,
            onToggleLaunchAtLogin: noOp,
            onAbout: onAbout ?? noOp,
            onQuit: noOp
        )
    }

    private static let noOp: () -> Void = {}
    private static func ignore<T>(_: T) { _ = T.self }

    static func pageTitles(_ menu: NSMenu) -> [String] {
        menu.items.prefix { !$0.isSeparatorItem }.map(\.title)
    }

    private static func pendingPage(_ name: String) -> WatchedPage {
        WatchedPage(url: URL(string: "https://example.com/\(name)")!, name: name)
    }

    private static func colouredPage(_ name: String, _ severity: Severity) -> WatchedPage {
        let url = URL(string: "https://example.com/\(name.replacingOccurrences(of: " ", with: "-"))")!
        return WatchedPage(
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: severity == .grey ? .green : severity,
                components: [],
                incidents: [],
                isUnreachable: severity == .grey
            )
        )
    }

    /// Overall stays green. The row colour comes from the red component.
    private static func pageWithRedComponent(_ name: String) -> WatchedPage {
        let url = URL(string: "https://example.com/\(name.replacingOccurrences(of: " ", with: "-"))")!
        let component = ComponentStatus(name: "API", severity: .red, statusText: "Major outage", id: "api")
        return WatchedPage(
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: .green,
                components: [component],
                incidents: [],
                isUnreachable: false
            )
        )
    }

    static func managedMenu(pages: [WatchedPage] = [], disabledManagedPages: [WatchedPage] = [],
                            onEnableManagedPage: ((UUID) -> Void)? = nil) -> NSMenu {
        MenuBuilder(handlers: handlers(onEnableManagedPage: onEnableManagedPage))
            .build(for: state(pages: pages, disabledManagedPages: disabledManagedPages))
    }

    func testRevealAndReloadConfigFollowRefresh() throws {
        let menu = Self.menu(page: Self.nestedPage(), onOpen: { _ in })
        let titles = menu.items.map(\.title)
        let refresh = try XCTUnwrap(titles.firstIndex(of: "Refresh"), titles.joined(separator: " | "))
        XCTAssertEqual(titles[refresh + 1], "Reveal Config File")
        XCTAssertEqual(titles[refresh + 2], "Reload Config")
        XCTAssertEqual(menu.items[refresh + 1].identifier?.rawValue, "reveal-config")
        XCTAssertEqual(menu.items[refresh + 2].identifier?.rawValue, "reload-config")
    }

    func testStatusRowsSortRedThenYellowThenGreyThenGreen() {
        let pages = [
            Self.colouredPage("Green A", .green),
            Self.pendingPage("Pending"),
            Self.colouredPage("Yellow", .yellow),
            Self.colouredPage("Unreachable", .grey),
            Self.colouredPage("Green B", .green),
            Self.pageWithRedComponent("Red Component")
        ]
        let menu = MenuBuilder(handlers: Self.handlers()).build(for: Self.state(pages: pages))
        XCTAssertEqual(
            Self.pageTitles(menu),
            ["Red Component", "Yellow", "Pending", "Unreachable", "Green A", "Green B"]
        )
    }

    func testStatusRowOrderFollowsASeverityChange() {
        let builder = MenuBuilder(handlers: Self.handlers())
        let green = Self.colouredPage("Was Green", .green)
        let red = Self.colouredPage("Was Red", .red)
        let first = builder.build(for: Self.state(pages: [green, red]))
        XCTAssertEqual(Self.pageTitles(first), ["Was Red", "Was Green"])

        var recovered = red
        recovered.snapshot = Self.colouredPage("Was Red", .green).snapshot
        let second = builder.build(for: Self.state(pages: [green, recovered]))
        XCTAssertEqual(Self.pageTitles(second), ["Was Green", "Was Red"])
    }

    func testRevealAndReloadConfigInvokeCallbacks() {
        var revealCount = 0
        var reloadCount = 0
        let menu = MenuBuilder(handlers: Self.handlers(
            onRevealConfig: { revealCount += 1 }, onReloadConfig: { reloadCount += 1 }
        )).build(for: Self.state(pages: []))
        Self.invoke(menu.item(withTitle: "Reveal Config File"))
        Self.invoke(menu.item(withTitle: "Reload Config"))
        XCTAssertEqual(revealCount, 1)
        XCTAssertEqual(reloadCount, 1)
    }
}
