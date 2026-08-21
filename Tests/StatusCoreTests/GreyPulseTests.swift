import XCTest
@testable import StatusCore

final class GreyPulseTests: XCTestCase {
    func testNoPulseWhenNothingIsUnreachable() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            GreyPulse.displayedSeverity(persistent: .green, hasUnreachable: false, now: now),
            .green
        )
    }

    func testAlreadyGreyStaysGrey() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            GreyPulse.displayedSeverity(persistent: .grey, hasUnreachable: true, now: now),
            .grey
        )
    }

    func testFlashesGreyAtStartOfWindow() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            GreyPulse.displayedSeverity(persistent: .green, hasUnreachable: true, now: now),
            .grey
        )
    }

    func testReturnsToPersistentColourAfterOneSecond() {
        let now = Date(timeIntervalSince1970: 1.5)
        XCTAssertEqual(
            GreyPulse.displayedSeverity(persistent: .red, hasUnreachable: true, now: now),
            .red
        )
    }

    func testFlashesAgainAtThirtySeconds() {
        let now = Date(timeIntervalSince1970: 30)
        XCTAssertEqual(
            GreyPulse.displayedSeverity(persistent: .yellow, hasUnreachable: true, now: now),
            .grey
        )
    }
}
