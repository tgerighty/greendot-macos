import XCTest
@testable import StatusCore

final class ConfigEncodingTests: XCTestCase {
    func testSetInsertionOrderDoesNotChangeSavedBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let forward = try Self.config(keys: ["alpha", "beta", "gamma", "delta"])
        let backward = try Self.config(keys: ["delta", "gamma", "beta", "alpha"])

        try store.save(forward)
        let first = try Data(contentsOf: store.configURL)
        try FileManager.default.removeItem(at: store.configURL)
        try store.save(backward)
        let second = try Data(contentsOf: store.configURL)

        XCTAssertEqual(first, second)
    }

    func testSavedConfigIsReadableWithSortedKeysAndPlainSlashes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(try Self.config(keys: ["beta", "alpha"]))
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))

        XCTAssertTrue(text.contains("\n"), text)
        XCTAssertTrue(text.contains("https://status.example.com/page"), text)
        XCTAssertFalse(text.contains("\\/"), text)

        let disabled = try Self.offset(of: "\"disabledComponentNames\"", in: text)
        let identifier = try Self.offset(of: "\"id\"", in: text)
        let name = try Self.offset(of: "\"name\"", in: text)
        let notifications = try Self.offset(of: "\"notificationsEnabled\"", in: text)
        let pageURL = try Self.offset(of: "\"url\"", in: text)
        XCTAssertTrue(disabled < identifier, text)
        XCTAssertTrue(identifier < name, text)
        XCTAssertTrue(name < notifications, text)
        XCTAssertTrue(notifications < pageURL, text)

        let alpha = try Self.offset(of: "\"alpha\"", in: text)
        let beta = try Self.offset(of: "\"beta\"", in: text)
        XCTAssertTrue(alpha < beta, text)
    }

    private static func config(keys: [String]) throws -> AppConfig {
        var disabled: Set<String> = []
        for key in keys {
            disabled.insert(key)
        }
        let page = WatchedPage(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            url: try XCTUnwrap(URL(string: "https://status.example.com/page")),
            name: "Example",
            notificationsEnabled: true,
            disabledComponentNames: disabled
        )
        return AppConfig(pages: [page])
    }

    private static func offset(of needle: String, in text: String) throws -> Int {
        let range = try XCTUnwrap(text.range(of: needle))
        return text.distance(from: text.startIndex, to: range.lowerBound)
    }
}
