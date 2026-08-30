import XCTest
@testable import StatusCore

final class ComponentTreeSeverityTests: XCTestCase {
    func testEnabledLeafSeverityPreservesNestedAndDisabledSemantics() {
        let tree = [
            ComponentStatus(
                name: "Group",
                severity: .yellow,
                statusText: "Degraded",
                id: "group",
                children: [
                    ComponentStatus(name: "Red", severity: .red, statusText: "Major outage", id: "red"),
                    ComponentStatus(name: "Green", severity: .green, statusText: "Operational", id: "green")
                ],
                isGroup: true
            )
        ]

        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: []), .red)
        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: ["red"]), .green)
        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: ["red", "green"]), .yellow)
        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: ["Group"]), .green)
    }

    func testEnabledLeafSeverityUsesEnabledDescendantsForNonGroupNodes() {
        let tree = [
            ComponentStatus(
                name: "Container",
                severity: .yellow,
                statusText: "Degraded",
                id: "container",
                children: [
                    ComponentStatus(name: "Child", severity: .red, statusText: "Major outage", id: "child")
                ]
            )
        ]

        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: []), .red)
        XCTAssertEqual(ComponentTree.enabledLeafSeverity(in: tree, disabledKeys: ["child"]), .yellow)
    }
}
