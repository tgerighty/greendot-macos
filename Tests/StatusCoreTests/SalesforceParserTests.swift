import XCTest
@testable import StatusCore

final class SalesforceParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://status.salesforce.com")!

    func testTwoIncidentsBuildsTreeAndOverallRed() throws {
        let data = Data("""
        [
          {
            "id": 20004433,
            "externalId": "95390343",
            "status": "Active",
            "type": "Disruption",
            "additionalInformation": "",
            "instanceKeys": ["AP52", "NA223", "USA1"],
            "serviceKeys": ["coreService"]
          },
          {
            "id": 20004430,
            "externalId": "icc-spiff",
            "status": "Active",
            "type": "Degradation",
            "additionalInformation": "Advanced Analytics data is stale",
            "instanceKeys": ["SPIFF-US1"],
            "serviceKeys": ["Spiff"]
          }
        ]
        """.utf8)
        let snap = try SalesforceParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .salesforce)
        XCTAssertEqual(snap.name, "Salesforce")
        XCTAssertEqual(snap.url, sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
        XCTAssertEqual(snap.components.count, 2)

        let first = snap.components[0]
        XCTAssertEqual(first.id, "20004433")
        XCTAssertEqual(first.name, "Disruption 95390343")
        XCTAssertTrue(first.isGroup)
        XCTAssertEqual(first.severity, .red)
        XCTAssertEqual(first.statusText, "Major outage")
        XCTAssertEqual(first.children.map(\.id), ["coreService"])
        XCTAssertEqual(first.children.map(\.name), ["coreService"])
        XCTAssertFalse(first.children[0].isGroup)
        XCTAssertEqual(first.children[0].severity, .red)
        XCTAssertEqual(first.children[0].statusText, "Major outage")

        let second = snap.components[1]
        XCTAssertEqual(second.id, "20004430")
        XCTAssertEqual(second.name, "Advanced Analytics data is stale")
        XCTAssertTrue(second.isGroup)
        XCTAssertEqual(second.severity, .yellow)
        XCTAssertEqual(second.statusText, "Degraded")
        XCTAssertEqual(second.children.map(\.id), ["Spiff"])
    }

    func testEmptyArrayIsGreenSalesforcePage() throws {
        let snap = try SalesforceParser.parse(data: Data("[]".utf8), sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .salesforce)
        XCTAssertEqual(snap.name, "Salesforce")
        XCTAssertEqual(snap.url, sourceURL)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
    }

    func testResolvedIncidentIsSkipped() throws {
        let data = Data("""
        [{
          "id": 1,
          "externalId": "old",
          "status": "Resolved",
          "type": "Disruption",
          "serviceKeys": ["coreService"]
        }]
        """.utf8)
        let snap = try SalesforceParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testMissingServiceKeysIsLeafGroup() throws {
        let data = Data("""
        [{
          "id": 9,
          "type": "Maintenance",
          "additionalInformation": "Core upgrade"
        }]
        """.utf8)
        let snap = try SalesforceParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components.count, 1)
        XCTAssertEqual(snap.components[0].id, "9")
        XCTAssertEqual(snap.components[0].name, "Core upgrade")
        XCTAssertTrue(snap.components[0].isGroup)
        XCTAssertTrue(snap.components[0].children.isEmpty)
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Maintenance")
    }

    func testObjectJSONIsNotThisProvider() {
        XCTAssertThrowsError(
            try SalesforceParser.parse(data: Data("{}".utf8), sourceURL: sourceURL)
        ) { error in
            XCTAssertEqual(error as? ParserError, .notThisProvider)
        }
    }
}
