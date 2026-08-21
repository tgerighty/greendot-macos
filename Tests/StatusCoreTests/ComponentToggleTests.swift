import XCTest
@testable import StatusCore

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
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
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
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try monitor.load()
        try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
        let id = monitor.pages[0].id
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)

        try monitor.toggleComponent(id: id, name: "Git")
        XCTAssertTrue(monitor.pages[0].disabledComponentNames.contains("Git"))
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)

        let loaded = Monitor(store: PageStore(directory: dir), client: client)
        try loaded.load()
        XCTAssertEqual(loaded.pages[0].disabledComponentNames, ["Git"])
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

    private func pageWith(components: [ComponentStatus], unreachable: Bool = false) -> WatchedPage {
        WatchedPage(
            url: URL(string: "https://status.openai.com")!,
            name: "OpenAI",
            snapshot: PageSnapshot(
                name: "OpenAI",
                url: URL(string: "https://status.openai.com")!,
                provider: .statuspage,
                overall: unreachable ? .grey : Aggregator.severity(from: components),
                components: components,
                incidents: [],
                isUnreachable: unreachable
            )
        )
    }
}
