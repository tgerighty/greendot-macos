import XCTest
@testable import StatusCore

final class RegionFilterTests: XCTestCase {
    func testNilRegionListStillUsesTheMuteList() {
        var page = Self.page(regions: nil, muted: ["AWS - Europe (Milan)"])
        page.snapshot = Self.snapshot([
            Self.region("AWS - Europe (Frankfurt)", "Databases", .green),
            Self.region("AWS - Europe (Milan)", "Databases", .red)
        ])
        XCTAssertEqual(page.displaySeverity, .green)
        XCTAssertEqual(page.enabledComponents.map(\.name), ["AWS - Europe (Frankfurt)"])
    }

    func testAllowlistHidesARegionTheVendorAddsLater() {
        var page = Self.page(regions: ["Frankfurt"], muted: [])
        page.snapshot = Self.snapshot([
            Self.region("AWS - Europe (Frankfurt)", "Databases", .green),
            Self.region("AWS - Europe (Milan)", "Databases", .red)
        ])
        XCTAssertEqual(page.displaySeverity, .green)
        XCTAssertEqual(page.enabledComponents.map(\.name), ["AWS - Europe (Frankfurt)"])
    }

    func testNewServiceInsideAnAllowedRegionStillCounts() {
        var page = Self.page(regions: ["Frankfurt"], muted: [])
        page.snapshot = Self.snapshot([
            Self.region("AWS - Europe (Frankfurt)", "Snowpark Container Services", .red)
        ])
        XCTAssertEqual(page.displaySeverity, .red)
        XCTAssertEqual(page.enabledComponents[0].children.map(\.name), ["Snowpark Container Services"])
    }

    func testRegionCodeMatchesTheComponentId() {
        var page = Self.page(regions: ["us-east-1"], muted: [])
        page.snapshot = Self.snapshot([
            Self.event(
                name: "Multiple services (N. Virginia)",
                id: "arn:aws:health:us-east-1::event/MULTI",
                childID: "ec2-us-east-1",
                severity: .yellow
            ),
            Self.event(
                name: "Multiple services (Bahrain)",
                id: "arn:aws:health:me-south-1::event/MULTI",
                childID: "ec2-me-south-1",
                severity: .red
            )
        ])
        XCTAssertEqual(page.displaySeverity, .yellow)
        XCTAssertEqual(page.enabledComponents.map(\.name), ["Multiple services (N. Virginia)"])
    }

    func testEmptyAllowlistMutesEveryComponent() {
        var page = Self.page(regions: [], muted: [])
        page.snapshot = Self.snapshot([
            Self.region("US (Virginia)", "Remote Access VPN", .red)
        ])
        XCTAssertEqual(page.displaySeverity, .green)
        XCTAssertTrue(page.enabledComponents.isEmpty)
    }

    private static func page(regions: [String]?, muted: Set<String>) -> WatchedPage {
        WatchedPage(
            url: URL(string: "https://status.example")!,
            name: "Example",
            disabledComponentNames: muted,
            enabledRegions: regions
        )
    }

    private static func snapshot(_ components: [ComponentStatus]) -> PageSnapshot {
        PageSnapshot(
            name: "Example",
            url: URL(string: "https://status.example")!,
            provider: .statuspage,
            overall: .red,
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func region(_ name: String, _ child: String, _ severity: Severity) -> ComponentStatus {
        ComponentStatus(
            name: name,
            severity: .green,
            statusText: "Operational",
            id: name,
            children: [
                ComponentStatus(name: child, severity: severity, statusText: severity.displayName, id: child)
            ],
            isGroup: true
        )
    }

    private static func event(
        name: String,
        id: String,
        childID: String,
        severity: Severity
    ) -> ComponentStatus {
        ComponentStatus(
            name: name,
            severity: .green,
            statusText: "Operational",
            id: id,
            children: [
                ComponentStatus(name: childID, severity: severity, statusText: severity.displayName, id: childID)
            ],
            isGroup: true
        )
    }
}
