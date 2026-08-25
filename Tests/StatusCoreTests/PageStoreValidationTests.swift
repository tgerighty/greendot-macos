import XCTest
@testable import StatusCore

final class PageStoreValidationTests: XCTestCase {
    func testLoadRejectsDuplicateWatchedPageIDs() throws {
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

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? StoreError, .corrupt)
        }
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
    }
}
