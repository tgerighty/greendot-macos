import XCTest
@testable import StatusCore

final class LegacyFieldTests: XCTestCase {
    func testVersion2ConfigIgnoresInlineSnapshotAndLaunchFlag() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(Self.sharedConfigJSON.utf8).write(to: store.configURL)

        let loaded = try store.load()

        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertEqual(loaded.pages[0].displaySeverity, .grey)
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
    }

    func testVersion2ConfigWithStateFileStillUsesStateSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        let state = """
        {
          "version": 2, "didSetLaunchAtLogin": true,
          "snapshots": {
            "00000000-0000-0000-0000-000000000001": {
              "url": "https://www.githubstatus.com",
              "snapshot": {"name": "GitHub", "url": "https://www.githubstatus.com", "provider": "statuspage",
                           "overall": "red", "components": [], "incidents": [], "isUnreachable": false}
            }
          }
        }
        """
        try Data(Self.sharedConfigJSON.utf8).write(to: store.configURL)
        try Data(state.utf8).write(to: store.stateURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .red)
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
    }

    func testVersion2ConfigIgnoresMalformedLegacyFields() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(Self.malformedLegacyConfigJSON.utf8).write(to: store.configURL)

        let loaded = try store.load()

        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.pages[0].name, "GitHub")
        XCTAssertEqual(loaded.pages[0].url.absoluteString, "https://www.githubstatus.com")
    }

    func testVersion1ConfigWithMalformedSnapshotStillLoads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        let config = """
        {
          "version": 1, "didSetLaunchAtLogin": true,
          "pages": [
            {
              "id": "00000000-0000-0000-0000-000000000001", "name": "GitHub",
              "url": "https://www.githubstatus.com", "notificationsEnabled": true,
              "disabledComponentNames": [], "snapshot": 42
            }
          ]
        }
        """
        try Data(config.utf8).write(to: store.configURL)

        let loaded = try store.load()

        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
    }

    func testWrongTypeInSettingsFieldIsStillCorrupt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        let config = """
        {
          "version": 2, "pages": [
            {
              "id": "00000000-0000-0000-0000-000000000001", "name": "GitHub",
              "url": "https://www.githubstatus.com", "notificationsEnabled": "yes",
              "disabledComponentNames": []
            }
          ]
        }
        """
        try Data(config.utf8).write(to: store.configURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? StoreError, .corrupt)
        }
    }

    /// A shared or hand-edited version-2 file whose legacy fields carry the wrong JSON type.
    private static let malformedLegacyConfigJSON = """
    {
      "version": 2, "didSetLaunchAtLogin": "false",
      "pages": [
        {
          "id": "00000000-0000-0000-0000-000000000001", "name": "GitHub",
          "url": "https://www.githubstatus.com", "notificationsEnabled": true,
          "disabledComponentNames": [], "snapshot": "stale"
        }
      ]
    }
    """

    /// A shared or hand-edited version-2 file that still carries machine-local fields.
    private static let sharedConfigJSON = """
    {
      "version": 2, "didSetLaunchAtLogin": true,
      "pages": [
        {
          "id": "00000000-0000-0000-0000-000000000001", "name": "GitHub",
          "url": "https://www.githubstatus.com", "notificationsEnabled": true, "disabledComponentNames": [],
          "snapshot": {
            "name": "GitHub", "url": "https://www.githubstatus.com", "provider": "statuspage",
            "overall": "yellow", "incidents": [], "isUnreachable": false,
            "components": [{"id": "c1", "name": "API", "severity": "yellow",
                            "statusText": "Degraded", "children": [], "isGroup": false}]
          }
        }
      ]
    }
    """
}
