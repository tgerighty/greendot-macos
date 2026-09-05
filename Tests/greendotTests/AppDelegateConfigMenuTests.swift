import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class AppDelegateConfigMenuTests: XCTestCase {
    private struct Seeded {
        let dir: URL
        let store: PageStore
        let monitor: Monitor
    }

    func testRevealConfigSelectsTheConfigFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        delegate.store = store
        var revealed: [URL] = []
        delegate.revealConfigFile = { revealed.append($0) }

        delegate.revealConfig()

        XCTAssertEqual(revealed, [store.configURL])
    }

    func testRevealConfigCreatesMissingConfigFile() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        delegate.store = store
        delegate.monitor = monitor
        var revealed: [URL] = []
        delegate.revealConfigFile = { revealed.append($0) }
        var presented: Error?
        delegate.presentError = { presented = $0 }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.configURL.path))

        delegate.revealConfig()

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.configURL.path))
        XCTAssertEqual(revealed, [store.configURL])
        XCTAssertNil(presented)
    }

    func testReloadConfigPicksUpAPageAddedOnDiskAndRestartsTheTimer() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["GREENDOT_POLL_SECONDS"] != nil,
            "env var overrides the configured interval"
        )
        _ = NSApplication.shared
        let seeded = try Self.seeded()
        let (store, monitor) = (seeded.store, seeded.monitor)
        defer { try? FileManager.default.removeItem(at: seeded.dir) }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])

        var next = try store.load()
        next.pollSeconds = 300
        next.pages.append(
            WatchedPage(url: try XCTUnwrap(URL(string: "https://status.openai.com")), name: "OpenAI")
        )
        try store.save(next)

        delegate.reloadConfig()

        XCTAssertNil(presented)
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub", "OpenAI"])
        XCTAssertEqual(delegate.pollTimer?.timeInterval, 300)
    }

    func testReloadConfigWithCorruptFilePresentsErrorAndKeepsPages() throws {
        _ = NSApplication.shared
        let seeded = try Self.seeded()
        let (store, monitor) = (seeded.store, seeded.monitor)
        defer { try? FileManager.default.removeItem(at: seeded.dir) }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        delegate.restartPollTimer(interval: 42)

        try Data("{".utf8).write(to: store.configURL)
        delegate.reloadConfig()

        XCTAssertEqual(presented as? StoreError, .corrupt)
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])
        XCTAssertEqual(delegate.pollTimer?.timeInterval, 42)
    }

    func testReloadConfigCancelsPendingFirstRunSeed() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(AppConfig())
        let client = ControllableHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { client.failAll() }
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }
        var seedFailure: Error?
        delegate.seedFailureDiagnostic = { seedFailure = $0 }

        delegate.startupTask = Task {
            await delegate.maybeSeedOpenAI(monitor: monitor, loadSucceeded: true, skipSeed: false)
        }
        let startup = delegate.startupTask
        await client.waitUntilRequestCount(1)

        var imported = AppConfig()
        imported.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "GitHub")
        ]
        try store.save(imported)

        delegate.reloadConfig()
        client.complete(request: 1, with: Data(Self.openAISummaryJSON.utf8))
        await startup?.value

        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])
        XCTAssertEqual(try store.load().pages.map(\.name), ["GitHub"])
        XCTAssertNil(presented)
        XCTAssertNil(seedFailure)
    }

    private static let openAISummaryJSON = """
    {
      "page": {"name": "OpenAI", "url": "https://status.openai.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    private static func seeded() throws -> Seeded {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "GitHub")
        ]
        try store.save(config)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        return Seeded(dir: dir, store: store, monitor: monitor)
    }
}
