import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class AppDelegateReloadRaceTests: XCTestCase {
    func testReloadDiscardsAnInFlightPollBeforeReading() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "Original")
        ]
        try store.save(config)
        let client = ControllableHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate(); client.failAll() }
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { _ in }

        let poll = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(1)
        // A hand edit of the file, as the user makes it. The store must not learn the new bytes yet.
        try Self.writeEditedConfig(config, to: store)

        delegate.reloadConfig()
        client.complete(request: 1, with: Data(Self.githubSummaryJSON.utf8))
        await poll.value

        XCTAssertEqual(monitor.pages.map(\.name), ["Edited"])
        XCTAssertEqual(try store.load().pages.map(\.name), ["Edited"])
        XCTAssertNil(monitor.pages.first?.snapshot)
    }

    /// The poll finishes first, so the identity check passes. The store still refuses the write.
    func testPollThatFinishesBeforeReloadKeepsTheEditedFileAndReportsIt() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "Original")
        ]
        try store.save(config)
        let client = ControllableHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate(); client.failAll() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        let poll = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(1)
        let edited = try Self.writeEditedConfig(config, to: store)
        client.complete(request: 1, with: Data(Self.githubSummaryJSON.utf8))
        await poll.value

        XCTAssertEqual(presented as? StoreError, .changedOnDisk)
        XCTAssertEqual(try Data(contentsOf: store.configURL), edited)
        XCTAssertEqual(monitor.pages.map(\.name), ["Original"])
        XCTAssertNil(monitor.pages.first?.snapshot)

        delegate.reloadConfig()
        XCTAssertEqual(monitor.pages.map(\.name), ["Edited"])
    }

    /// Writes config.json behind the store's back, as a hand edit or a copied-in file does.
    @discardableResult
    private static func writeEditedConfig(_ config: AppConfig, to store: PageStore) throws -> Data {
        var edited = config
        edited.pages[0].name = "Edited"
        let data = try JSONEncoder().encode(edited)
        try data.write(to: store.configURL, options: .atomic)
        return data
    }

    private static let githubSummaryJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """
}
