import XCTest
@testable import StatusCore

final class SlackParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://slack-status.com/")!

    func testOkWithNoIncidentsIsGreen() throws {
        let data = Data("""
        {"status":"ok","active_incidents":[]}
        """.utf8)
        let snap = try SlackParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .slack)
        XCTAssertEqual(snap.name, "Slack")
        XCTAssertEqual(snap.url, URL(string: "https://slack-status.com")!)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testOutageIncidentIsRedWithServiceChildren() throws {
        let data = Data("""
        {
          "status": "active",
          "active_incidents": [
            {
              "id": 9,
              "title": "Messaging delayed",
              "type": "outage",
              "services": ["Messaging", "Apps"]
            }
          ]
        }
        """.utf8)
        let snap = try SlackParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].id, "9")
        XCTAssertEqual(snap.components[0].name, "Messaging delayed")
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Messaging", "Apps"])
        XCTAssertEqual(snap.components[0].children[0].severity, .red)
    }

    func testMissingActiveIncidentsIsNotThisProvider() {
        XCTAssertThrowsError(try SlackParser.parse(data: Data("{\"status\":\"ok\"}".utf8), sourceURL: sourceURL)) {
            XCTAssertEqual($0 as? ParserError, .notThisProvider)
        }
    }
}
