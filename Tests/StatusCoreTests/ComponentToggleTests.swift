import XCTest
@testable import StatusCore
import TestSupport

final class ComponentToggleTests: XCTestCase {
    func testDisplaySeverityIgnoresDisabledRedComponent() {
        var page = pageWith(components: [
            ComponentStatus(name: "API", severity: .green, statusText: "Operational"),
            ComponentStatus(name: "Chat", severity: .red, statusText: "Major outage")
        ])
        XCTAssertEqual(page.displaySeverity, .red)

        page.disabledComponentNames.insert("Chat")
        XCTAssertEqual(page.displaySeverity, .green)
    }

    func testEnabledComponentsOmitsDisabledNames() {
        var page = pageWith(components: [
            ComponentStatus(name: "API", severity: .green, statusText: "Operational"),
            ComponentStatus(name: "Chat", severity: .yellow, statusText: "Degraded")
        ])
        page.disabledComponentNames = ["Chat"]
        XCTAssertEqual(page.enabledComponents.map(\.name), ["API"])
    }

    func testUnreachableStaysGreyEvenIfComponentsDisabled() {
        var page = pageWith(
            components: [ComponentStatus(name: "API", severity: .green, statusText: "Operational")],
            unreachable: true
        )
        page.disabledComponentNames = ["API"]
        XCTAssertEqual(page.displaySeverity, .grey)
    }

    func testToggleComponentPersists() async throws {
        let (directory, monitor) = try await monitorWithGitHubOutage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = monitor.pages[0].id
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)

        try monitor.toggleComponent(id: id, name: "Git")
        XCTAssertTrue(monitor.pages[0].disabledComponentNames.contains("Git"))
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)

        let loaded = Monitor(store: PageStore(directory: directory), client: MapHTTPClient())
        try loaded.load()
        XCTAssertEqual(loaded.pages[0].disabledComponentNames, ["Git"])
    }

    func testSetAllComponentsOffThenOn() async throws {
        let (directory, monitor) = try await monitorWithGitHubOutage()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = monitor.pages[0].id
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)

        try monitor.setAllComponents(id: id, enabled: false)
        XCTAssertTrue(monitor.pages[0].enabledComponents.isEmpty)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)

        try monitor.setAllComponents(id: id, enabled: true)
        XCTAssertFalse(monitor.pages[0].enabledComponents.isEmpty)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)
    }

    func testToggleGroupTurnsChildrenOffAndOn() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        {
          "page": {"name": "Box", "url": "https://status.box.com"},
          "status": {"indicator": "none"},
          "components": [
            {"id": "g1", "name": "Box Web Application", "status": "operational", "group": true},
            {"id": "c1", "name": "Login/SSO", "status": "major_outage", "group": false, "group_id": "g1"},
            {"id": "c2", "name": "Search", "status": "operational", "group": false, "group_id": "g1"}
          ],
          "incidents": []
        }
        """
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Data(json.utf8), 200)])
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try await monitor.add(url: URL(string: "https://status.box.com")!, name: nil)
        let id = monitor.pages[0].id
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)

        try monitor.toggleComponent(id: id, name: "g1")
        XCTAssertTrue(monitor.pages[0].enabledComponents.isEmpty)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)

        try monitor.toggleComponent(id: id, name: "g1")
        XCTAssertEqual(monitor.pages[0].enabledComponents.first?.children.count, 2)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)
    }

    func testDisablingAGroupHidesItsChildren() {
        var page = pageWith(components: [
            ComponentStatus(
                name: "Box Web Application",
                severity: .green,
                statusText: "Operational",
                id: "g1",
                children: [
                    ComponentStatus(name: "Login/SSO", severity: .red, statusText: "Major outage", id: "c1"),
                    ComponentStatus(name: "Search", severity: .green, statusText: "Operational", id: "c2")
                ],
                isGroup: true
            )
        ])
        XCTAssertEqual(page.displaySeverity, .red)
        page.disabledComponentNames.insert("g1")
        XCTAssertEqual(page.enabledComponents, [])
        XCTAssertEqual(page.displaySeverity, .green)
    }

    func testIsComponentEnabledChecksIdAndName() {
        var page = pageWith(components: [
            ComponentStatus(name: "Login/SSO", severity: .red, statusText: "Major outage", id: "c1")
        ])
        let component = ComponentStatus(name: "Login/SSO", severity: .red, statusText: "Major outage", id: "c1")
        XCTAssertTrue(page.isComponentEnabled(component))

        page.disabledComponentNames = ["c1"]
        XCTAssertFalse(page.isComponentEnabled(component))

        page.disabledComponentNames = ["Login/SSO"]
        XCTAssertFalse(page.isComponentEnabled(component))
    }

    func testDisablingOneChildLeavesSiblings() {
        var page = pageWith(components: [
            ComponentStatus(
                name: "Box Web Application",
                severity: .green,
                statusText: "Operational",
                id: "g1",
                children: [
                    ComponentStatus(name: "Login/SSO", severity: .red, statusText: "Major outage", id: "c1"),
                    ComponentStatus(name: "Search", severity: .green, statusText: "Operational", id: "c2")
                ],
                isGroup: true
            )
        ])
        page.disabledComponentNames.insert("c1")
        XCTAssertEqual(page.enabledComponents.first?.children.map(\.name), ["Search"])
        XCTAssertEqual(page.displaySeverity, .green)
    }

    func testComponentTreeFindMatchesIdOrNameAndWalksChildren() {
        let tree = boxTree()
        XCTAssertEqual(ComponentTree.find("c1", in: tree)?.name, "Login/SSO")
        XCTAssertEqual(ComponentTree.find("Login/SSO", in: tree)?.id, "c1")
        XCTAssertEqual(ComponentTree.find("Box Web Application", in: tree)?.id, "g1")
        XCTAssertNil(ComponentTree.find("missing", in: tree))
    }

    func testComponentTreeCollectIncludesSelfAndDescendants() {
        XCTAssertEqual(ComponentTree.collect(boxTree()[0]).map(\.id), ["g1", "c1", "c2"])
    }

    func testComponentTreeKeysIncludeIdAndName() {
        XCTAssertEqual(
            ComponentTree.componentKeys(boxTree()),
            ["g1", "Box Web Application", "c1", "Login/SSO", "c2", "Search"]
        )
    }

    func testToggleComponentByNameDisablesIdAndDescendantKeys() async throws {
        let (directory, monitor) = try await boxOutageMonitor()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = monitor.pages[0].id

        try monitor.toggleComponent(id: id, name: "Box Web Application")
        XCTAssertEqual(
            monitor.pages[0].disabledComponentNames,
            ["g1", "Box Web Application", "c1", "Login/SSO", "c2", "Search"]
        )
    }

    func testSetAllComponentsRecordsEveryIdAndName() async throws {
        let (directory, monitor) = try await boxOutageMonitor()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = monitor.pages[0].id

        try monitor.setAllComponents(id: id, enabled: false)
        XCTAssertEqual(
            monitor.pages[0].disabledComponentNames,
            ["g1", "Box Web Application", "c1", "Login/SSO", "c2", "Search"]
        )
    }

    func testOldConfigWithoutDisabledNamesStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let raw = """
        {"version":1,"pages":[],"didSetLaunchAtLogin":false}
        """
        try Data(raw.utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = PageStore(directory: dir)
        let config = try store.load()
        XCTAssertTrue(config.pages.isEmpty)
    }

    private func boxTree() -> [ComponentStatus] {
        [
            ComponentStatus(
                name: "Box Web Application",
                severity: .green,
                statusText: "Operational",
                id: "g1",
                children: [
                    ComponentStatus(name: "Login/SSO", severity: .red, statusText: "Major outage", id: "c1"),
                    ComponentStatus(name: "Search", severity: .green, statusText: "Operational", id: "c2")
                ],
                isGroup: true
            )
        ]
    }

    private func monitorWithGitHubOutage() async throws -> (directory: URL, monitor: Monitor) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [
            {"name": "API", "status": "operational", "group": false},
            {"name": "Git", "status": "major_outage", "group": false}
          ],
          "incidents": []
        }
        """
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Data(json.utf8), 200)])
        let monitor = Monitor(store: PageStore(directory: directory), client: client)
        try monitor.load()
        try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
        return (directory, monitor)
    }

    private func boxOutageMonitor() async throws -> (directory: URL, monitor: Monitor) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let json = """
        {
          "page": {"name": "Box", "url": "https://status.box.com"},
          "status": {"indicator": "none"},
          "components": [
            {"id": "g1", "name": "Box Web Application", "status": "operational", "group": true},
            {"id": "c1", "name": "Login/SSO", "status": "major_outage", "group": false, "group_id": "g1"},
            {"id": "c2", "name": "Search", "status": "operational", "group": false, "group_id": "g1"}
          ],
          "incidents": []
        }
        """
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Data(json.utf8), 200)])
        let monitor = Monitor(store: PageStore(directory: directory), client: client)
        try await monitor.add(url: URL(string: "https://status.box.com")!, name: nil)
        return (directory, monitor)
    }

    private func pageWith(components: [ComponentStatus], unreachable: Bool = false) -> WatchedPage {
        let pageURL = testURL(host: "status.openai.com")
        return WatchedPage(
            url: pageURL,
            name: "OpenAI",
            snapshot: PageSnapshot(
                name: "OpenAI",
                url: pageURL,
                provider: .statuspage,
                overall: unreachable ? .grey : Aggregator.severity(from: components),
                components: components,
                incidents: [],
                isUnreachable: unreachable
            )
        )
    }
}

extension ComponentToggleTests {
    func testMissingSnapshotIsGrey() {
        let page = WatchedPage(
            url: testURL(host: "status.openai.com"),
            name: "OpenAI"
        )

        XCTAssertEqual(page.displaySeverity, .grey)
    }

    func testEmptyComponentsUsePageOverall() {
        for severity in [Severity.red, .yellow] {
            let page = pageWith(overall: severity)
            XCTAssertEqual(page.displaySeverity, severity)
        }
    }

    func testAllDisabledComponentsRemainGreenWhenPageOverallIsRed() {
        var page = pageWith(
            overall: .red,
            components: [ComponentStatus(name: "API", severity: .red, statusText: "Major outage")]
        )
        page.disabledComponentNames = ["API"]

        XCTAssertEqual(page.displaySeverity, .green)
    }

    private func pageWith(
        overall: Severity,
        components: [ComponentStatus] = [],
        unreachable: Bool = false
    ) -> WatchedPage {
        let pageURL = testURL(host: "status.openai.com")
        return WatchedPage(
            url: pageURL,
            name: "OpenAI",
            snapshot: PageSnapshot(
                name: "OpenAI",
                url: pageURL,
                provider: .statuspage,
                overall: overall,
                components: components,
                incidents: [],
                isUnreachable: unreachable
            )
        )
    }
}
