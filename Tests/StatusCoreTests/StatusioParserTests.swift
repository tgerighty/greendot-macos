import XCTest
@testable import StatusCore

final class StatusioParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://status.gitlab.com")!

    func testOperationalPageBuildsTree() throws {
        let data = Data("""
        {
          "result": {
            "status_overall": {"status": "Operational", "status_code": 100},
            "status": [
              {
                "id": "web",
                "name": "Website",
                "status": "Operational",
                "status_code": 100,
                "containers": [
                  {"id": "gce", "name": "Google Compute Engine", "status": "Operational", "status_code": 100}
                ]
              }
            ],
            "incidents": [],
            "maintenance": {"active": [], "upcoming": []}
          }
        }
        """.utf8)
        let snap = try StatusioParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .statusio)
        XCTAssertEqual(snap.name, "status.gitlab.com")
        XCTAssertEqual(snap.url, sourceURL)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertEqual(snap.components.count, 1)
        XCTAssertEqual(snap.components[0].id, "web")
        XCTAssertEqual(snap.components[0].name, "Website")
        XCTAssertTrue(snap.components[0].isGroup)
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].children.map(\.id), ["gce"])
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Google Compute Engine"])
        XCTAssertFalse(snap.components[0].children[0].isGroup)
    }

    func testDegradedContainerMakesPageYellow() throws {
        let data = Data("""
        {
          "result": {
            "status_overall": {"status": "Degraded performance", "status_code": 300},
            "status": [
              {
                "id": "eco",
                "name": "Ecosystem",
                "status": "Degraded performance",
                "status_code": 300,
                "containers": [
                  {"id": "portal", "name": "Support Portal", "status": "Degraded performance", "status_code": 300}
                ]
              }
            ]
          }
        }
        """.utf8)
        let snap = try StatusioParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
        XCTAssertEqual(snap.components[0].children[0].severity, .yellow)
    }

    func testServiceDisruptionIsRed() throws {
        let data = Data("""
        {
          "result": {
            "status_overall": {"status": "Service disruption", "status_code": 500},
            "status": [{"id": "api", "name": "API", "status": "Service disruption", "status_code": 500, "containers": []}]
          }
        }
        """.utf8)
        let snap = try StatusioParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
        XCTAssertTrue(snap.components[0].children.isEmpty)
    }

    func testMissingResultIsNotThisProvider() {
        XCTAssertThrowsError(try StatusioParser.parse(data: Data("{}".utf8), sourceURL: sourceURL)) {
            XCTAssertEqual($0 as? ParserError, .notThisProvider)
        }
    }
}
