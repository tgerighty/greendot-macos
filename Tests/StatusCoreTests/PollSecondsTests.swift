import XCTest
@testable import StatusCore
import TestSupport

final class PollSecondsTests: XCTestCase {
    func testMissingPollSecondsDecodesToSixty() throws {
        let config = try Self.load(#"{"version":2,"pages":[]}"#)
        XCTAssertEqual(config.pollSeconds, 60)
    }

    func testInvalidPollSecondsDecodesToSixty() throws {
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":0,"pages":[]}"#).pollSeconds, 60)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":-5,"pages":[]}"#).pollSeconds, 60)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":"soon","pages":[]}"#).pollSeconds, 60)
    }

    func testValidPollSecondsDecodes() throws {
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":15,"pages":[]}"#).pollSeconds, 15)
        XCTAssertEqual(try Self.load(#"{"version":2,"pollSeconds":0.5,"pages":[]}"#).pollSeconds, 0.5)
    }

    func testSavedConfigAlwaysWritesPollSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pollSeconds = 300
        try store.save(config)
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        XCTAssertTrue(text.contains("pollSeconds"), text)
        XCTAssertEqual(try store.load().pollSeconds, 300)
    }

    func testMonitorExposesLoadedPollSeconds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(#"{"version":2,"pollSeconds":120,"pages":[]}"#.utf8).write(to: store.configURL)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        XCTAssertEqual(monitor.pollSeconds, 60)
        try monitor.load()
        XCTAssertEqual(monitor.pollSeconds, 120)
    }

    private static func load(_ json: String) throws -> AppConfig {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(json.utf8).write(to: store.configURL)
        return try store.load()
    }
}
