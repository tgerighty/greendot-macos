import XCTest
@testable import StatusCore
import TestSupport

/// config.json belongs to the user. A save must not write over a file that changed under the store.
final class ChangedOnDiskTests: XCTestCase {
    private static let editedConfigJSON = Data(#"{"version":2,"pollSeconds":60,"pages":[]}"#.utf8)

    private static let statuspageJSON = Data("""
    {
      "page": {"name": "A", "url": "https://a.example"},
      "status": {"indicator": "minor"},
      "components": [{"name": "API", "status": "degraded_performance", "group": false}],
      "incidents": [{"name": "API slow"}]
    }
    """.utf8)

    func testSaveRefusesToOverwriteConfigChangedOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [try Self.page(name: "GitHub")]
        try store.save(config)
        _ = try store.load()
        let stateBefore = try Self.inode(store.stateURL)

        try Self.editedConfigJSON.write(to: store.configURL, options: .atomic)
        var mutated = config
        mutated.pages[0].name = "GitHub renamed"

        XCTAssertThrowsError(try store.save(mutated)) {
            XCTAssertEqual($0 as? StoreError, .changedOnDisk)
        }
        XCTAssertEqual(try Data(contentsOf: store.configURL), Self.editedConfigJSON)
        XCTAssertEqual(try Self.inode(store.stateURL), stateBefore)
    }

    func testUserEditAdoptsTheChangedFileAndKeepsTheEdit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        let page = try Self.page(name: "GitHub")
        config.pages = [page]
        try store.save(config)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()

        var edited = config
        edited.pages[0].name = "Edited"
        try PageStore(directory: dir).save(edited)

        XCTAssertNoThrow(try monitor.toggleNotifications(id: page.id))

        XCTAssertEqual(monitor.pages.map(\.name), ["Edited"])
        XCTAssertEqual(monitor.pages.map(\.notificationsEnabled), [false])
        let saved = try store.load()
        XCTAssertEqual(saved.pages.map(\.name), ["Edited"])
        XCTAssertEqual(saved.pages.map(\.notificationsEnabled), [false])
    }

    func testEditAppliesComponentSelectionToTheChangedFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        let page = try Self.page(name: "GitHub")
        config.pages = [page]
        try store.save(config)
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(byPath: ["/api/v2/summary.json": (Self.statuspageJSON, 200)])
        )
        try monitor.load()

        var edited = config
        edited.pages[0].name = "Edited"
        try PageStore(directory: dir).save(edited)

        try await monitor.edit(
            id: page.id,
            url: page.url,
            name: "From editor",
            disabledComponentNames: ["API"]
        )

        let saved = try store.load()
        XCTAssertEqual(saved.pages.map(\.name), ["From editor"])
        XCTAssertEqual(saved.pages[0].disabledComponentNames, ["API"])
    }

    func testReloadAdoptsChangedFileAndAllowsSaves() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [try Self.page(name: "GitHub")]
        try store.save(config)
        _ = try store.load()

        try Self.editedConfigJSON.write(to: store.configURL, options: .atomic)
        let loaded = try store.load()

        XCTAssertNoThrow(try store.save(loaded))
        XCTAssertTrue(try store.load().pages.isEmpty)
    }

    func testFreshStoreSavesWithoutLoading() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var config = AppConfig()
        config.pages = [try Self.page(name: "GitHub")]
        try PageStore(directory: dir).save(config)

        let store = PageStore(directory: dir)
        var mutated = config
        mutated.pages[0].name = "GitHub renamed"

        XCTAssertNoThrow(try store.save(mutated))
        XCTAssertEqual(try store.load().pages.map(\.name), ["GitHub renamed"])
    }

    func testMonitorPollDoesNotOverwriteExternallyChangedConfig() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage)]
        try store.save(config)
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Self.statuspageJSON, 200)])
        let monitor = Monitor(store: store, client: client)
        try monitor.load()

        try Self.editedConfigJSON.write(to: store.configURL, options: .atomic)

        do {
            _ = try await monitor.pollAll()
            XCTFail("the poll saved over the edited file")
        } catch {
            XCTAssertEqual(error as? StoreError, .changedOnDisk)
        }
        XCTAssertEqual(try Data(contentsOf: store.configURL), Self.editedConfigJSON)
        XCTAssertEqual(monitor.pages.map(\.name), ["A"])
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)
    }

    private static func inode(_ url: URL) throws -> NSNumber {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.systemFileNumber] as? NSNumber)
    }

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
