import XCTest
@testable import greendot

final class PollIntervalTests: XCTestCase {
    func testPollIntervalUsesDefaultForInvalidValues() {
        let invalidValues: [String?] = [
            nil,
            "",
            "not-a-number",
            "0",
            "-10",
            "NaN",
            "infinity",
            "-infinity"
        ]

        for value in invalidValues {
            XCTAssertEqual(
                AppDelegate.pollInterval(from: value, configured: 60),
                60,
                "Expected default for \(value ?? "missing")"
            )
        }
    }

    func testPollIntervalAcceptsFinitePositiveValues() {
        for value in ["0.25", "60", "3600"] {
            XCTAssertEqual(AppDelegate.pollInterval(from: value, configured: 60), Double(value))
        }
    }

    func testPollIntervalUsesConfiguredValueWhenEnvIsMissingOrInvalid() {
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: 300), 300)
        XCTAssertEqual(AppDelegate.pollInterval(from: "not-a-number", configured: 300), 300)
        XCTAssertEqual(AppDelegate.pollInterval(from: "0", configured: 300), 300)
    }

    func testPollIntervalEnvOverridesConfiguredValue() {
        XCTAssertEqual(AppDelegate.pollInterval(from: "15", configured: 300), 15)
    }

    func testPollIntervalFallsBackToDefaultForInvalidConfiguredValue() {
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: 0), 60)
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: -1), 60)
        XCTAssertEqual(AppDelegate.pollInterval(from: nil, configured: .nan), 60)
    }
}
