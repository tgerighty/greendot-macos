import XCTest
@testable import StatusCore

final class OktaParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://status.okta.com/")!

    func testActiveDisruptionBuildsCellChildren() throws {
        let html = wrap(
            incidents: """
            [{"Id":"a9C1","Name":"I-1","Incident_Title__c":"Login failures",\
            "Status__c":"Investigating","Category__c":"Service Disruption",\
            "Impacted_Cells__c":"okta.com:9;oktapreview.com:1"}]
            """,
            outages: "[]"
        )
        let snap = try OktaParser.parse(data: Data(html.utf8), sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .okta)
        XCTAssertEqual(snap.name, "Okta")
        XCTAssertEqual(snap.url, URL(string: "https://status.okta.com")!)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
        XCTAssertEqual(snap.components.count, 1)
        let incident = snap.components[0]
        XCTAssertEqual(incident.id, "a9C1")
        XCTAssertEqual(incident.name, "Login failures")
        XCTAssertTrue(incident.isGroup)
        XCTAssertEqual(incident.severity, .red)
        XCTAssertEqual(incident.statusText, "Major outage")
        XCTAssertEqual(incident.children.map(\.id), ["okta.com:9", "oktapreview.com:1"])
        XCTAssertEqual(incident.children.map(\.name), ["okta.com:9", "oktapreview.com:1"])
        XCTAssertEqual(incident.children[0].severity, .red)
    }

    func testResolvedOnlyIsGreenEmptyTree() throws {
        let html = wrap(
            incidents: """
            [{"Id":"a9C2","Name":"I-2","Incident_Title__c":"Old issue",\
            "Status__c":"Resolved","Category__c":"Service Disruption",\
            "Impacted_Cells__c":"okta.com:1"}]
            """,
            outages: "[]"
        )
        let snap = try OktaParser.parse(data: Data(html.utf8), sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .okta)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testDegradationAndPlannedOutageAreYellow() throws {
        let html = wrap(
            incidents: """
            [{"Id":"a9C3","Name":"I-3","Incident_Title__c":"Slow SSO",\
            "Status__c":"Monitoring","Category__c":"Service Degradation",\
            "Impacted_Cells__c":"okta.com:2"}]
            """,
            outages: """
            [{"Id":"P-1","OutageDetails__c":"Cell OK9 maintenance"}]
            """
        )
        let snap = try OktaParser.parse(data: Data(html.utf8), sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components.map(\.id), ["a9C3", "P-1"])
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
        XCTAssertEqual(snap.components[1].name, "Cell OK9 maintenance")
        XCTAssertEqual(snap.components[1].severity, .yellow)
        XCTAssertEqual(snap.components[1].statusText, "Maintenance")
        XCTAssertTrue(snap.components[1].children.isEmpty)
    }

    func testRejectsHTMLWithoutIncidents() {
        XCTAssertThrowsError(
            try OktaParser.parse(data: Data("<html><body>no</body></html>".utf8), sourceURL: sourceURL)
        )
    }

    private func wrap(incidents: String, outages: String) -> String {
        """
        <html><body>
        <span data-id="incidents">\(incidents)</span>
        <span data-id="planned-outages">\(outages)</span>
        </body></html>
        """
    }
}
