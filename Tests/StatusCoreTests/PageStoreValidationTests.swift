import XCTest
@testable import StatusCore

final class PageStoreValidationTests: XCTestCase {
    func testLoadKeepsDuplicateIDPagesAndMintsNewIDs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "url": "https://first.example.com",
              "name": "First"
            },
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "url": "https://second.example.com",
              "name": "Second"
            }
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First", "Second"])
        XCTAssertEqual(config.pages[0].id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertNotEqual(config.pages[1].id, config.pages[0].id)
        // A second load returns the same ids, which proves the file was rewritten.
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testLoadMintsNewIDWhenIDsRepeatInDifferentHexCase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {
              "id": "00000000-0000-0000-0000-00000000000A",
              "url": "https://first.example.com",
              "name": "First"
            },
            {
              "id": "00000000-0000-0000-0000-00000000000a",
              "url": "https://second.example.com",
              "name": "Second"
            }
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First", "Second"])
        XCTAssertEqual(config.pages[0].id.uuidString, "00000000-0000-0000-0000-00000000000A")
        XCTAssertNotEqual(config.pages[1].id, config.pages[0].id)
        // A second load returns the same ids, which proves the file was rewritten.
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testLoadMintsMissingPageIDAndRewritesFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {"url": "https://first.example.com", "name": "First"}
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First"])
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        XCTAssertTrue(text.contains(config.pages[0].id.uuidString), text)
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testLoadMintsIDWhenIDStringIsNotAUUID() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {
          "version": 1,
          "pages": [
            {"id": "not-a-uuid", "url": "https://first.example.com", "name": "First"}
          ],
          "didSetLaunchAtLogin": false
        }
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        try Data(json.utf8).write(to: store.configURL)

        let config = try store.load()

        XCTAssertEqual(config.pages.map(\.name), ["First"])
        let text = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        XCTAssertTrue(text.contains(config.pages[0].id.uuidString), text)
        XCTAssertEqual(try store.load().pages.map(\.id), config.pages.map(\.id))
    }

    func testCleanLoadDoesNotRewriteConfigFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let page = WatchedPage(
            url: try XCTUnwrap(URL(string: "https://first.example.com")),
            name: "First"
        )
        try store.save(AppConfig(pages: [page]))
        let before = try Self.inode(store.configURL)

        _ = try store.load()

        XCTAssertEqual(try Self.inode(store.configURL), before)
    }

    private static func inode(_ url: URL) throws -> NSNumber {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.systemFileNumber] as? NSNumber)
    }

    func testSaveRejectsDuplicateWatchedPageIDsBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let duplicateID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let first = WatchedPage(
            id: duplicateID,
            url: try XCTUnwrap(URL(string: "https://first.example.com")),
            name: "First"
        )
        let second = WatchedPage(
            id: duplicateID,
            url: try XCTUnwrap(URL(string: "https://second.example.com")),
            name: "Second"
        )
        let config = AppConfig(pages: [first, second])

        XCTAssertThrowsError(try store.save(config)) { error in
            XCTAssertEqual(error as? StoreError, .corrupt)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.configURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))
    }
}
