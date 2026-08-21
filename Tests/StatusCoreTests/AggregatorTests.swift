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
