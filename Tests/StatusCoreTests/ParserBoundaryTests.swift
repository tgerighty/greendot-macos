import XCTest
@testable import StatusCore

final class ParserBoundaryTests: XCTestCase {
    private let url = URL(string: "https://status.example.com")!

    func testStatuspageMissingComponentStatusIsNotGreen() throws {
        let data = Data(#"{"status":{"indicator":"critical"},"components":[{"name":"API"}]}"#.utf8)
        let snapshot = try StatuspageParser.parse(data: data, sourceURL: url)
        XCTAssertEqual(snapshot.components[0].severity, .yellow)
        XCTAssertEqual(WatchedPage(url: url, name: "API", snapshot: snapshot).displaySeverity, .yellow)
    }

    func testInstatusMissingComponentStatusIsNotGreen() throws {
        let data = Data(#"{"page":{"status":"HASISSUES"},"components":[{"name":"API"}]}"#.utf8)
        let snapshot = try InstatusParser.parse(data: data, sourceURL: url)
        XCTAssertEqual(snapshot.components[0].severity, .yellow)
        XCTAssertEqual(WatchedPage(url: url, name: "API", snapshot: snapshot).displaySeverity, .yellow)
    }

    func testOktaRejectsMalformedRequiredIncidents() {
        for incidents in ["[", "{}", "[1]"] {
            let html = "<span data-id=\"incidents\">\(incidents)</span>"
            XCTAssertThrowsError(try OktaParser.parse(data: Data(html.utf8), sourceURL: url))
        }
    }

    func testOktaRejectsPresentMalformedPlannedOutages() {
        let html = "<span data-id=\"incidents\">[]</span><span data-id=\"planned-outages\">bad</span>"
        XCTAssertThrowsError(try OktaParser.parse(data: Data(html.utf8), sourceURL: url))
    }

    func testIcingaFractionalStateIsUnknown() throws {
        let hosts = Data(#"{"results":[{"attrs":{"name":"api","state":0.5}}]}"#.utf8)
        let services = Data(#"{"results":[]}"#.utf8)
        let snapshot = try IcingaParser.parse(hosts: hosts, services: services, sourceURL: url)
        XCTAssertEqual(snapshot.components[0].children[0].severity, .yellow)
    }

    func testStatusioFractionalCodeIsUnknown() throws {
        for code in ["100.5", "100.000000000000001"] {
            let data = Data("{\"result\":{\"status_overall\":{\"status_code\":\(code)}}}".utf8)
            let snapshot = try StatusioParser.parse(data: data, sourceURL: url)
            XCTAssertEqual(snapshot.overall, .yellow, code)
        }
    }

    func testStatusioFractionalComponentCodeIsUnknown() throws {
        let json = #"{"result":{"status_overall":{"status_code":100},"status":["#
            + #"{"name":"API","status_code":100.000000000000001}]}}"#
        let data = Data(json.utf8)
        let snapshot = try StatusioParser.parse(data: data, sourceURL: url)
        XCTAssertEqual(snapshot.components[0].severity, .yellow)
    }

    func testIncidentRootsRejectNonObjectMembers() {
        let data = Data("[1]".utf8)
        XCTAssertThrowsError(try AwsParser.parse(data: data, sourceURL: url))
        XCTAssertThrowsError(try GoogleParser.parse(data: data, sourceURL: url))
        XCTAssertThrowsError(try SalesforceParser.parse(data: data, sourceURL: url))
    }

    func testPresentMalformedIncidentCollectionsAreRejected() {
        let incidentio = Data(#"{"summary":{"ongoing_incidents":{}}}"#.utf8)
        let apple = Data(#"{"services":[{"serviceName":"API","events":{}}]}"#.utf8)
        let heroku = Data(#"{"status":[{"system":"API","status":"green"}],"incidents":{}}"#.utf8)
        let scheduled = Data(#"{"status":[{"system":"API","status":"green"}],"scheduled":{}}"#.utf8)
        XCTAssertThrowsError(try IncidentioParser.parse(data: incidentio, sourceURL: url))
        XCTAssertThrowsError(try AppleParser.parse(data: apple, sourceURL: url))
        XCTAssertThrowsError(try HerokuParser.parse(data: heroku, sourceURL: url))
        XCTAssertThrowsError(try HerokuParser.parse(data: scheduled, sourceURL: url))
    }
}
