import XCTest
@testable import StatusCore

final class StateFileSplitTests: XCTestCase {
    func testSaveThenLoadRoundTripsSnapshotsAndLaunchFlagThroughStateFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]

        try store.save(config)

        let configText = try XCTUnwrap(String(data: try Data(contentsOf: store.configURL), encoding: .utf8))
        let stateText = try XCTUnwrap(String(data: try Data(contentsOf: store.stateURL), encoding: .utf8))
        XCTAssertFalse(configText.contains("snapshot"), configText)
        XCTAssertFalse(configText.contains("didSetLaunchAtLogin"), configText)
        XCTAssertTrue(configText.contains("\"version\""), configText)
        XCTAssertTrue(stateText.contains("didSetLaunchAtLogin"), stateText)
        XCTAssertTrue(stateText.contains("snapshots"), stateText)

        let loaded = try store.load()
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.pages.map(\.name), ["GitHub"])
        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .green)
        XCTAssertEqual(loaded.pages[0].snapshot?.components.map(\.name), ["API"])
    }

    func testLoadWithoutStateFileDropsSnapshotsAndLaunchFlag() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]
        try store.save(config)

        try FileManager.default.removeItem(at: store.stateURL)

        let loaded = try store.load()
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.pages.map(\.name), ["GitHub"])
        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertEqual(loaded.pages[0].displaySeverity, .grey)
    }

    func testCorruptStateFileIsIgnored() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]
        try store.save(config)

        try Data("{".utf8).write(to: store.stateURL)

        let loaded = try store.load()
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
        XCTAssertNil(loaded.pages[0].snapshot)
        XCTAssertEqual(loaded.pages.map(\.name), ["GitHub"])
    }

    func testVersion1FileLoadsInlineStateAndNextSaveSplitsIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        try Data(Self.legacyConfigJSON.utf8).write(to: store.configURL)

        let loaded = try store.load()
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .yellow)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.stateURL.path))

        try store.save(loaded)

        let configData = try Data(contentsOf: store.configURL)
        let configText = try XCTUnwrap(String(data: configData, encoding: .utf8))
        let stateText = try XCTUnwrap(String(data: try Data(contentsOf: store.stateURL), encoding: .utf8))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: configData) as? [String: Any])
        XCTAssertFalse(configText.contains("snapshot"), configText)
        XCTAssertEqual(root["version"] as? Int, 2)
        XCTAssertNil(root["didSetLaunchAtLogin"])
        XCTAssertTrue(stateText.contains("00000000-0000-0000-0000-000000000001"), stateText)
        XCTAssertEqual(try store.load().pages[0].snapshot?.overall, .yellow)
    }

    func testStateFileSnapshotBeatsInlineVersion1Snapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        let state = """
        {
          "version": 2,
          "didSetLaunchAtLogin": false,
          "snapshots": {
            "00000000-0000-0000-0000-000000000001": {
              "name": "GitHub",
              "url": "https://www.githubstatus.com",
              "provider": "statuspage",
              "overall": "red",
              "components": [],
              "incidents": [],
              "isUnreachable": false
            }
          }
        }
        """
        try Data(Self.legacyConfigJSON.utf8).write(to: store.configURL)
        try Data(state.utf8).write(to: store.stateURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .red)
        XCTAssertFalse(loaded.didSetLaunchAtLogin)
    }

    func testSaveKeepsBothFilesAtMode0600EvenWhenTheBytesDoNotChange() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try Self.page(name: "GitHub")]

        try store.save(config)

        XCTAssertEqual(try Self.mode(store.configURL), 0o600)
        XCTAssertEqual(try Self.mode(store.stateURL), 0o600)

        // A file copied in from another machine can carry mode 0644 with identical bytes.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.configURL.path)
        try store.save(config)

        XCTAssertEqual(try Self.mode(store.configURL), 0o600)
    }

    private static func mode(_ url: URL) throws -> Int16 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).int16Value
    }

    /// A version-1 file: the snapshot is inline and `didSetLaunchAtLogin` is at the top level.
    private static let legacyConfigJSON = """
    {
      "version": 1,
      "didSetLaunchAtLogin": true,
      "pages": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "url": "https://www.githubstatus.com",
          "name": "GitHub",
          "notificationsEnabled": true,
          "disabledComponentNames": [],
          "snapshot": {
            "name": "GitHub",
            "url": "https://www.githubstatus.com",
            "provider": "statuspage",
            "overall": "yellow",
            "components": [
              {"id": "c1", "name": "API", "severity": "yellow",
               "statusText": "Degraded", "children": [], "isGroup": false}
            ],
            "incidents": [],
            "isUnreachable": false
          }
        }
      ]
    }
    """

    private static func page(name: String) throws -> WatchedPage {
        let url = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        return WatchedPage(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: .green,
                components: [ComponentStatus(name: "API", severity: .green, statusText: "Operational")],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}
