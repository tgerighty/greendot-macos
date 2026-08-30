import StatusCore
import XCTest
@testable import greendot

final class ComponentSelectionIndexTests: XCTestCase {
    func testSummarizesEnabledCountsForEveryNestedSubtree() {
        let login = ComponentStatus(
            name: "Login",
            severity: .red,
            statusText: "Major outage",
            id: "login"
        )
        let search = ComponentStatus(
            name: "Search",
            severity: .green,
            statusText: "Operational",
            id: "search"
        )
        let nested = ComponentStatus(
            name: "Nested",
            severity: .green,
            statusText: "Operational",
            id: "nested",
            children: [search],
            isGroup: true
        )
        let root = ComponentStatus(
            name: "Root",
            severity: .green,
            statusText: "Operational",
            id: "root",
            children: [login, nested],
            isGroup: true
        )

        let index = ComponentSelectionIndex(
            components: [root],
            disabledKeys: ["login", "Nested"]
        )

        XCTAssertEqual(index["login"], ComponentSelectionSummary(enabledCount: 0, totalCount: 1))
        XCTAssertEqual(index["search"], ComponentSelectionSummary(enabledCount: 1, totalCount: 1))
        XCTAssertEqual(index["nested"], ComponentSelectionSummary(enabledCount: 1, totalCount: 2))
        XCTAssertEqual(index["root"], ComponentSelectionSummary(enabledCount: 2, totalCount: 4))
        XCTAssertEqual(index.all, ComponentSelectionSummary(enabledCount: 2, totalCount: 4))
    }
}
