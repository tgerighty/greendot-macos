import XCTest
@testable import StatusCore

final class GoogleParserTests: XCTestCase {
    func testClosedIncidentsAreSkipped() throws {
        let data = Data("""
        [{
          "id": "old",
          "external_desc": "Past outage",
          "severity": "high",
          "end": "2026-09-01T00:00:00+00:00",
          "affected_products": [{"id": "gce", "title": "Compute Engine"}]
        }]
        """.utf8)
        let snap = try GoogleParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.cloud.google.com")!
        )
        XCTAssertEqual(snap.provider, .google)
        XCTAssertEqual(snap.name, "Google Cloud")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testOpenHighSeverityIsRedWithProducts() throws {
        let data = Data("""
        [{
          "id": "now",
          "external_desc": "Network isolation\\nin us-central1",
          "severity": "high",
          "end": null,
          "affected_products": [
            {"id": "gce", "title": "Compute Engine"},
            {"id": "gke", "title": "Kubernetes Engine"}
          ]
        }]
        """.utf8)
        let snap = try GoogleParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.cloud.google.com")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].name, "Network isolation")
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Compute Engine", "Kubernetes Engine"])
    }

    func testWorkspaceAndFirebaseNames() throws {
        let empty = Data("[]".utf8)
        let workspace = try GoogleParser.parse(
            data: empty,
            sourceURL: URL(string: "https://www.google.com/appsstatus/dashboard")!
        )
        XCTAssertEqual(workspace.name, "Google Workspace")
        let firebase = try GoogleParser.parse(
            data: empty,
            sourceURL: URL(string: "https://status.firebase.google.com")!
        )
        XCTAssertEqual(firebase.name, "Firebase")
    }
}
