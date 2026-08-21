import XCTest
@testable import StatusCore

final class AggregatorTests: XCTestCase {
    func testEmptyListIsGreen() {
        XCTAssertEqual(Aggregator.barSeverity(from: []), .green)
    }

    func testRedBeatsYellowAndGreen() {
        let snapshots = [
            snap(.green),
            snap(.yellow),
            snap(.red)
        ]
        XCTAssertEqual(Aggregator.barSeverity(from: snapshots), .red)
    }

    func testYellowBeatsGreen() {
        XCTAssertEqual(
            Aggregator.barSeverity(from: [snap(.green), snap(.yellow)]),
            .yellow
        )
    }

    func testGreyDoesNotDriveTheBarWhenARealStatusExists() {
        XCTAssertEqual(
            Aggregator.barSeverity(from: [snap(.green), snap(.grey)]),
            .green
        )
    }

    func testBarIsGreyWhenEveryPageIsGrey() {
        XCTAssertEqual(
            Aggregator.barSeverity(from: [snap(.grey), snap(.grey)]),
            .grey
        )
    }

    func testEmptyComponentsAreGreen() {
        XCTAssertEqual(Aggregator.severity(from: []), .green)
    }

    func testComponentRedBeatsYellowAndGreen() {
        let components = [
            component(.green),
            component(.yellow),
            component(.red)
        ]
        XCTAssertEqual(Aggregator.severity(from: components), .red)
    }

    func testComponentYellowBeatsGreen() {
        XCTAssertEqual(
            Aggregator.severity(from: [component(.green), component(.yellow)]),
            .yellow
        )
    }

    func testGreyDoesNotDriveComponentsWhenARealStatusExists() {
        XCTAssertEqual(
            Aggregator.severity(from: [component(.green), component(.grey)]),
            .green
        )
    }

    func testComponentsAreGreyWhenEveryComponentIsGrey() {
        XCTAssertEqual(
            Aggregator.severity(from: [component(.grey), component(.grey)]),
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
