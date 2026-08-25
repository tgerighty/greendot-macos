import XCTest
@testable import StatusCore
import TestSupport

final class MonitorRefreshTransactionTests: XCTestCase {
    private let greenStatuspageJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    private let yellowStatuspageJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "minor"},
      "components": [{"name": "API", "status": "degraded_performance", "group": false}],
      "incidents": []
    }
    """

    private let redStatuspageJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [{"name": "API", "status": "major_outage", "group": false}],
      "incidents": []
    }
    """

    private let editedRedStatuspageJSON = """
    {
      "page": {"name": "Edited Status", "url": "https://status.example.com"},
      "status": {"indicator": "major"},
      "components": [{"name": "API", "status": "major_outage", "group": false}],
      "incidents": []
    }
    """

    func testPollThrowsPersistenceErrorAndLeavesWatchedPageUnchanged() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: dir, pageURL: url)
        let changedJSON = redStatuspageJSON
        let monitor = try loadedMonitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(changedJSON.utf8), 200)
            ])
        )
        let before = monitor.pages[0]

        try FileManager.default.removeItem(at: store.configURL)
        try FileManager.default.createDirectory(at: store.configURL, withIntermediateDirectories: true)

        do {
            _ = try await monitor.pollAll()
            XCTFail("expected the persistence error")
        } catch {
            let persistenceError = error as NSError
            XCTAssertEqual(persistenceError.domain, NSCocoaErrorDomain)
            XCTAssertEqual(persistenceError.code, NSFileWriteUnknownError)
        }
        XCTAssertEqual(monitor.pages, [before])
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)
    }

    func testNewestStartedOverlappingPollWinsWhenOlderPollCompletesLast() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: dir, pageURL: url)
        let client = ControllableHTTPClient()
        defer { client.failAll() }
        let monitor = try loadedMonitor(store: store, client: client)

        let pollA = Task { try await monitor.pollAll() }
        await client.waitUntilRequestCount(1)
        let pollB = Task { try await monitor.pollAll() }
        await client.waitUntilRequestCount(2)

        client.complete(request: 2, with: Data(redStatuspageJSON.utf8))
        _ = try await pollB.value
        client.complete(request: 1, with: Data(yellowStatuspageJSON.utf8))
        _ = try await pollA.value

        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
        let persisted = try store.load()
        XCTAssertEqual(persisted.pages[0].snapshot?.overall, .red)
    }

    func testPollPreservesNotificationToggleMadeWhileRequestIsInFlight() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: dir, pageURL: url)
        let client = ControllableHTTPClient()
        defer { client.failAll() }
        let monitor = try loadedMonitor(store: store, client: client)
        let pageID = monitor.pages[0].id

        let poll = Task { try await monitor.pollAll() }
        await client.waitUntilRequestCount(1)
        try monitor.toggleNotifications(id: pageID)
        XCTAssertFalse(monitor.pages[0].notificationsEnabled)

        client.complete(request: 1, with: Data(redStatuspageJSON.utf8))
        _ = try await poll.value

        XCTAssertFalse(monitor.pages[0].notificationsEnabled)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
        let persisted = try store.load().pages[0]
        XCTAssertFalse(persisted.notificationsEnabled)
        XCTAssertEqual(persisted.snapshot?.overall, .red)
    }

    func testCompletedEditSurvivesOlderInFlightPoll() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let originalURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let editedURL = try XCTUnwrap(URL(string: "https://status.example.com"))
        let store = try await seedStore(at: dir, pageURL: originalURL)
        let client = ControllableHTTPClient()
        defer { client.failAll() }
        let monitor = try loadedMonitor(store: store, client: client)
        let pageID = monitor.pages[0].id

        let poll = Task { try await monitor.pollAll() }
        await client.waitUntilRequestCount(1)
        let edit = Task {
            try await monitor.edit(id: pageID, url: editedURL, name: "Edited Status")
        }
        await client.waitUntilRequestCount(2)

        client.complete(request: 2, with: Data(editedRedStatuspageJSON.utf8))
        try await edit.value
        client.complete(request: 1, with: Data(yellowStatuspageJSON.utf8))
        _ = try await poll.value

        let page = monitor.pages[0]
        XCTAssertEqual(page.url, editedURL)
        XCTAssertEqual(page.name, "Edited Status")
        XCTAssertEqual(page.snapshot?.overall, .red)
        XCTAssertEqual(page.snapshot?.url, editedURL)

        let persisted = try store.load().pages[0]
        XCTAssertEqual(persisted.url, editedURL)
        XCTAssertEqual(persisted.name, "Edited Status")
        XCTAssertEqual(persisted.snapshot?.overall, .red)
        XCTAssertEqual(persisted.snapshot?.url, editedURL)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func seedStore(at directory: URL, pageURL: URL) async throws -> PageStore {
        let store = PageStore(directory: directory)
        let seeded = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenStatuspageJSON.utf8), 200)
            ])
        )
        try seeded.load()
        try await seeded.add(url: pageURL, name: nil)
        return store
    }

    private func loadedMonitor(store: PageStore, client: HTTPClient) throws -> Monitor {
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        return monitor
    }
}
