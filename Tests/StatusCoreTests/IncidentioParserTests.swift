import XCTest
@testable import StatusCore

final class IncidentioParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://status.incident.io")!

    func testEmptyOngoingIsGreen() throws {
        let data = Data("""
        {"summary": {"name": "incident.io", "public_url": "https://status.incident.io/", "ongoing_incidents": []}}
        """.utf8)
        let snap = try IncidentioParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .incidentio)
        XCTAssertEqual(snap.name, "incident.io")
        XCTAssertEqual(snap.url, URL(string: "https://status.incident.io/")!)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testMajorIncidentIsRedWithComponents() throws {
        let data = Data("""
        {
          "summary": {
            "name": "incident.io",
            "ongoing_incidents": [
              {
                "id": "inc1",
                "name": "API errors",
                "impact": "major",
                "affected_components": [{"id": "api", "name": "API"}]
              }
            ]
          }
        }
        """.utf8)
        let snap = try IncidentioParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].name, "API errors")
        XCTAssertEqual(snap.components[0].children.map(\.name), ["API"])
    }

    func testMissingSummaryIsNotThisProvider() {
        XCTAssertThrowsError(try IncidentioParser.parse(data: Data("{}".utf8), sourceURL: sourceURL)) {
            XCTAssertEqual($0 as? ParserError, .notThisProvider)
        }
    }
}
