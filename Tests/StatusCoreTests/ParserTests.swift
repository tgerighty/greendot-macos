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
        XCTAssertEqual(snap.components.map(\.name), ["API", "Group"])
        XCTAssertEqual(snap.components.first?.statusText, "Operational")
        XCTAssertTrue(snap.components[1].isGroup)
        XCTAssertTrue(snap.components[1].children.isEmpty)
    }

    func testStatuspageNestsGroupChildren() throws {
        let data = Data("""
        {
          "page": {"name": "Box", "url": "https://status.box.com"},
          "status": {"indicator": "none"},
          "components": [
            {"id": "g1", "name": "Box Web Application", "status": "operational", "group": true},
            {"id": "c1", "name": "Login/SSO", "status": "operational", "group": false, "group_id": "g1"},
            {"id": "c2", "name": "Search", "status": "degraded_performance", "group": false, "group_id": "g1"},
            {"id": "c3", "name": "Content API", "status": "operational", "group": false}
          ],
          "incidents": []
        }
        """.utf8)
        let snap = try StatuspageParser.parse(data: data, sourceURL: URL(string: "https://status.box.com")!)
        XCTAssertEqual(snap.components.map(\.name), ["Box Web Application", "Content API"])
        XCTAssertTrue(snap.components[0].isGroup)
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Login/SSO", "Search"])
        XCTAssertEqual(snap.components[0].children[1].severity, .yellow)
        XCTAssertEqual(snap.components[1].name, "Content API")
        XCTAssertTrue(snap.components[1].children.isEmpty)
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
        XCTAssertEqual(snap.components.map(\.name), ["IaaS"])
        XCTAssertTrue(snap.components[0].isGroup)
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Object Storage"])
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

    func testFlashdutyOperational() throws {
        let data = Data("""
        {
          "schema_version": "1.0",
          "generated_at": "2026-08-21T09:24:11Z",
          "poll_after_seconds": 30,
          "max_stale_seconds": 120,
          "page": {
            "name": "DeepSeek",
            "url": "https://status.deepseek.com"
          },
          "overall": {
            "status": "operational"
          },
          "ongoing_incidents": [],
          "in_progress_maintenances": [],
          "scheduled_maintenances": []
        }
        """.utf8)
        let snap = try FlashdutyParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.deepseek.com")!
        )
        XCTAssertEqual(snap.provider, .flashduty)
        XCTAssertEqual(snap.name, "DeepSeek")
        XCTAssertEqual(snap.url, URL(string: "https://status.deepseek.com")!)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
        XCTAssertTrue(snap.incidents.isEmpty)
        XCTAssertFalse(snap.isUnreachable)
    }

    func testFlashdutyPartialOutageIncludesIncident() throws {
        let data = Data("""
        {
          "schema_version": "1.0",
          "page": {"name": "Example Status", "url": "https://status.example.com"},
          "overall": {"status": "partial_outage"},
          "ongoing_incidents": [
            {
              "id": "1024",
              "title": "Elevated API error rates",
              "phase": "investigating",
              "impact": "partial_outage",
              "url": "https://status.example.com/incidents/1024",
              "affected_components": [
                {"id": "cmp-1", "name": "Public API", "status": "partial_outage"}
              ]
            }
          ],
          "in_progress_maintenances": [],
          "scheduled_maintenances": []
        }
        """.utf8)
        let snap = try FlashdutyParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com")!
        )
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.incidents, [
            Incident(
                title: "Elevated API error rates",
                url: URL(string: "https://status.example.com/incidents/1024")
            )
        ])
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testFlashdutyFullOutageIsRed() throws {
        let data = Data("""
        {
          "schema_version": "1.0",
          "page": {"name": "Example Status"},
          "overall": {"status": "full_outage"},
          "ongoing_incidents": [],
          "in_progress_maintenances": [],
          "scheduled_maintenances": []
        }
        """.utf8)
        let snap = try FlashdutyParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com")!
        )
        XCTAssertEqual(snap.overall, .red)
    }

    func testFlashdutyInProgressMaintenanceIsIncidentAndScheduledIsIgnored() throws {
        let data = Data("""
        {
          "schema_version": "1.0",
          "page": {"name": "Example Status"},
          "overall": {"status": "maintenance"},
          "ongoing_incidents": [],
          "in_progress_maintenances": [
            {
              "id": "m1",
              "title": "Database upgrade",
              "phase": "ongoing",
              "url": "https://status.example.com/maintenance/m1"
            }
          ],
          "scheduled_maintenances": [
            {"id": "m2", "title": "Next week window", "phase": "scheduled"}
          ]
        }
        """.utf8)
        let snap = try FlashdutyParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com")!
        )
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.incidents, [
            Incident(
                title: "Database upgrade",
                url: URL(string: "https://status.example.com/maintenance/m1")
            )
        ])
    }

    func testFlashdutyRejectsStatuspageJSON() {
        let data = Data("""
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """.utf8)
        XCTAssertThrowsError(
            try FlashdutyParser.parse(data: data, sourceURL: URL(string: "https://www.githubstatus.com")!)
        )
    }
}
