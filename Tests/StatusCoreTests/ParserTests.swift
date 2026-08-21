import XCTest
@testable import StatusCore

final class ParserTests: XCTestCase {
    func testStatuspageOperational() throws {
        let data = Data("""
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none", "description": "All Systems Operational"},
          "components": [
            {"name": "API", "status": "operational", "group": false},
            {"name": "Group", "status": "operational", "group": true}
          ],
          "incidents": []
        }
        """.utf8)
        let snap = try StatuspageParser.parse(data: data, sourceURL: URL(string: "https://www.githubstatus.com")!)
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components.map(\.name), ["API"])
        XCTAssertEqual(snap.components.first?.statusText, "Operational")
    }

    func testStatuspageCriticalIsRed() throws {
        let data = Data("""
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "critical"},
          "components": [{"name": "API", "status": "major_outage", "group": false}],
          "incidents": [{"name": "API down"}]
        }
        """.utf8)
        let snap = try StatuspageParser.parse(data: data, sourceURL: URL(string: "https://www.githubstatus.com")!)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.first?.severity, .red)
        XCTAssertEqual(snap.incidents.first?.title, "API down")
    }

    func testStatuspageRejectsInstatusJSON() {
        let data = Data("""
        {"page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"}}
        """.utf8)
        XCTAssertThrowsError(
            try StatuspageParser.parse(data: data, sourceURL: URL(string: "https://instat.us")!)
        )
    }

    func testInstatusUp() throws {
        let data = Data("""
        {"page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"}}
        """.utf8)
        let snap = try InstatusParser.parse(data: data, sourceURL: URL(string: "https://instat.us")!)
        XCTAssertEqual(snap.provider, .instatus)
        XCTAssertEqual(snap.overall, .green)
    }

    func testInstatusMajorIssueIsRed() throws {
        let data = Data("""
        {
          "page": {"name": "Instatus", "url": "https://instat.us", "status": "HASISSUES"},
          "activeIncidents": [{"name": "API", "impact": "MAJOROUTAGE"}]
        }
        """.utf8)
        let snap = try InstatusParser.parse(data: data, sourceURL: URL(string: "https://instat.us")!)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents.first?.title, "API")
    }

    func testStatuspalFlattensLeaves() throws {
        let data = Data("""
        {
          "status_page": {"name": "Interconnect", "url": "https://status.example"},
          "current_status_type": null,
          "services": [
            {
              "name": "IaaS",
              "current_incident_type": null,
              "children": [
                {"name": "Object Storage", "current_incident_type": null, "children": []}
              ]
            }
          ],
          "incidents": []
        }
        """.utf8)
        let snap = try StatuspalParser.parse(data: data, sourceURL: URL(string: "https://status.example")!)
        XCTAssertEqual(snap.provider, .statuspal)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components.map(\.name), ["Object Storage"])
    }

    func testStatuspalMajorIsRed() throws {
        let data = Data("""
        {
          "status_page": {"name": "Acme"},
          "current_status_type": "major",
          "services": [],
          "incidents": [{"title": "Outage"}]
        }
        """.utf8)
        let snap = try StatuspalParser.parse(data: data, sourceURL: URL(string: "https://status.example")!)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents.first?.title, "Outage")
    }
}
