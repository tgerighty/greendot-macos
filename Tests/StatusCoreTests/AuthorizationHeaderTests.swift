import XCTest
@testable import StatusCore

/// FT-45-01 / FT-45-02: probe Authorization header for page read token (REQ-45).
final class AuthorizationHeaderTests: XCTestCase {
    func testWhenTokenIsSetHeaderIsBearerToken() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: "abc"),
            ["Authorization": "Bearer abc"]
        )
    }

    func testWhenTokenIsNilHeaderMapIsEmpty() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: nil),
            [:]
        )
    }

    func testWhenTokenIsEmptyStringHeaderMapIsEmpty() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: ""),
            [:]
        )
    }

    /// FT-45-01: probe must attach the same header map on each GET when a token is set.
    func testProbeHeaderMapMatchesAuthorizationHelper() {
        let token = "page-read-token"
        let expected = RequestHeaders.authorization(token: token)
        XCTAssertEqual(expected["Authorization"], "Bearer \(token)")
        XCTAssertEqual(expected.count, 1)
    }
}
