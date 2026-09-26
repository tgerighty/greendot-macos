import XCTest
@testable import StatusCore

final class AggregatorTests: XCTestCase {
    func testEmptyListIsGreen() {
        XCTAssertEqual(Aggregator.fromSeverities([]), .green)
    }

    func testRedBeatsYellowAndGreen() {
        let snapshots = [
            snap(.green),
            snap(.yellow),
            snap(.red)
        ]
        XCTAssertEqual(Aggregator.fromSeverities(snapshots.map(\.overall)), .red)
    }

    func testYellowBeatsGreen() {
        XCTAssertEqual(
            Aggregator.fromSeverities([snap(.green), snap(.yellow)].map(\.overall)),
            .yellow
        )
    }

    func testGreyDoesNotDriveTheBarWhenARealStatusExists() {
        XCTAssertEqual(
            Aggregator.fromSeverities([snap(.green), snap(.grey)].map(\.overall)),
            .green
        )
    }

    func testBarIsGreyWhenEveryPageIsGrey() {
        XCTAssertEqual(
            Aggregator.fromSeverities([snap(.grey), snap(.grey)].map(\.overall)),
            .grey
        )
    }

    func testEmptyComponentsAreGreen() {
        XCTAssertEqual(Aggregator.fromSeverities([]), .green)
    }

    func testComponentRedBeatsYellowAndGreen() {
        let components = [
            component(.green),
            component(.yellow),
            component(.red)
        ]
        XCTAssertEqual(Aggregator.fromSeverities(components.map(\.severity)), .red)
    }

    func testComponentYellowBeatsGreen() {
        XCTAssertEqual(
            Aggregator.fromSeverities([component(.green), component(.yellow)].map(\.severity)),
            .yellow
        )
    }

    func testGreyDoesNotDriveComponentsWhenARealStatusExists() {
        XCTAssertEqual(
            Aggregator.fromSeverities([component(.green), component(.grey)].map(\.severity)),
            .green
        )
    }

    func testComponentsAreGreyWhenEveryComponentIsGrey() {
        XCTAssertEqual(
            Aggregator.fromSeverities([component(.grey), component(.grey)].map(\.severity)),
            .grey
        )
    }

    func testFromSeveritiesEmptyIsGreen() {
        XCTAssertEqual(Aggregator.fromSeverities([]), .green)
    }

    func testFromSeveritiesRedBeatsYellowAndGreen() {
        XCTAssertEqual(Aggregator.fromSeverities([.green, .yellow, .red]), .red)
    }

    func testFromSeveritiesGreyDoesNotBeatGreen() {
        XCTAssertEqual(Aggregator.fromSeverities([.green, .grey]), .green)
    }

    func testFromSeveritiesAllGreyIsGrey() {
        XCTAssertEqual(Aggregator.fromSeverities([.grey]), .grey)
    }

    private func component(_ severity: Severity) -> ComponentStatus {
        ComponentStatus(name: "c", severity: severity, statusText: severity.rawValue)
    }

    private func snap(_ severity: Severity) -> PageSnapshot {
        PageSnapshot(
            name: "x",
            url: URL(string: "https://example.com")!,
            provider: .statuspage,
            overall: severity,
            components: [],
            incidents: [],
            isUnreachable: severity == .grey
        )
    }
}
