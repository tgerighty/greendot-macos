import XCTest
@testable import StatusCore

final class AppleParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://www.apple.com/support/systemstatus/")!

    func testServicesWithoutEventsAreOmitted() throws {
        let data = Data("""
        {"drMessage": null, "services": [{"serviceName": "App Store", "events": []}]}
        """.utf8)
        let snap = try AppleParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .apple)
        XCTAssertEqual(snap.name, "Apple")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }

    func testOutageEventIsRed() throws {
        let data = Data("""
        {
          "services": [
            {
              "serviceName": "iCloud Drive",
              "events": [
                {"statusType": "Outage", "eventStatus": "ongoing", "message": "Some users affected"}
              ]
            }
          ]
        }
        """.utf8)
        let snap = try AppleParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].name, "iCloud Drive")
        XCTAssertEqual(snap.components[0].children[0].name, "Some users affected")
        XCTAssertEqual(snap.components[0].children[0].severity, .red)
    }

    func testResolvedEventsAreSkipped() throws {
        let data = Data("""
        {
          "services": [
            {
              "serviceName": "App Store",
              "events": [
                {"statusType": "Issue", "eventStatus": "resolved", "message": "Fixed"}
              ]
            }
          ]
        }
        """.utf8)
        let snap = try AppleParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
    }
}
