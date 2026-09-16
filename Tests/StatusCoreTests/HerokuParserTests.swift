import XCTest
@testable import StatusCore

final class HerokuParserTests: XCTestCase {
    private let sourceURL = URL(string: "https://status.heroku.com")!

    func testGreenSystemsAreOperational() throws {
        let data = Data("""
        {
          "status": [
            {"system": "Apps", "status": "green"},
            {"system": "Data", "status": "green"}
          ],
          "incidents": [],
          "scheduled": [
            {"id": 1, "title": "Future window", "state": "upcoming"}
          ]
        }
        """.utf8)
        let snap = try HerokuParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.provider, .heroku)
        XCTAssertEqual(snap.name, "Heroku")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components.map(\.name), ["Apps", "Data"])
        XCTAssertEqual(snap.components.map(\.severity), [.green, .green])
    }

    func testRedSystemAndInProgressMaintenance() throws {
        let data = Data("""
        {
          "status": [{"system": "Apps", "status": "red"}],
          "incidents": [{"id": 8, "title": "API down"}],
          "scheduled": [{"id": 2, "title": "Platform work", "state": "in-progress"}]
        }
        """.utf8)
        let snap = try HerokuParser.parse(data: data, sourceURL: sourceURL)
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.map(\.name), ["Apps", "API down", "Platform work"])
        XCTAssertEqual(snap.components[2].severity, .yellow)
        XCTAssertEqual(snap.components[2].statusText, "Maintenance")
    }
}
