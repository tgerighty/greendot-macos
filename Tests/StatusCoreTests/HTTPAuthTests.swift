import XCTest
@testable import StatusCore

final class HTTPAuthTests: XCTestCase {
    func testBasicHeaderFromUserinfoAndStripsRequestURL() {
        let url = URL(string: "https://tg_alert_monitor:s3cret@icinga.example:5665/v1")!
        let requestURL = HTTPAuth.requestURL(url)
        XCTAssertEqual(requestURL, URL(string: "https://icinga.example:5665/v1"))
        XCTAssertNil(requestURL.user)
        XCTAssertNil(requestURL.password)
        let headers = HTTPAuth.headers(for: url)
        let expected = Data("tg_alert_monitor:s3cret".utf8).base64EncodedString()
        XCTAssertEqual(headers["Authorization"], "Basic \(expected)")
        XCTAssertEqual(headers["Accept"], "application/json")
    }

    func testNoUserinfoOmitsAuthorization() {
        let url = URL(string: "https://www.githubstatus.com")!
        XCTAssertEqual(HTTPAuth.requestURL(url), url)
        XCTAssertTrue(HTTPAuth.headers(for: url).isEmpty)
    }

    func testAllowsInsecureTLSOnlyForIcingaAPI() {
        XCTAssertTrue(TLSTrust.allowsInsecureServerTrust(
            for: URL(string: "https://icinga.example:5665/v1")!
        ))
        XCTAssertFalse(TLSTrust.allowsInsecureServerTrust(
            for: URL(string: "https://www.githubstatus.com")!
        ))
        XCTAssertFalse(TLSTrust.allowsInsecureServerTrust(
            for: URL(string: "https://status.okta.com")!
        ))
    }
}
