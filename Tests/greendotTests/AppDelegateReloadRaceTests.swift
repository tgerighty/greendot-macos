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
        var edited = config
        edited.pages[0].name = "Edited"
        try store.save(edited)

        delegate.reloadConfig()
        client.complete(request: 1, with: Data(Self.githubSummaryJSON.utf8))
        await poll.value

        XCTAssertEqual(monitor.pages.map(\.name), ["Edited"])
        XCTAssertEqual(try store.load().pages.map(\.name), ["Edited"])
        XCTAssertNil(monitor.pages.first?.snapshot)
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
