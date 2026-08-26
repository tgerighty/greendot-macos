import Foundation
import XCTest
import StatusCore
import TestSupport
@testable import greendot

@MainActor
final class AppDelegateRefreshErrorTests: XCTestCase {
    private let greenJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    private let redJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [{"name": "API", "status": "major_outage", "group": false}],
      "incidents": []
    }
    """

    private let redWithoutComponentsJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [],
      "incidents": []
    }
    """

    func testSuccessfulPollDeliversToastThroughInjectedAdapter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: directory, pageURL: pageURL)
        let monitor = Monitor(
            store: store,
            client: SequenceHTTPClient(responses: [Data(redJSON.utf8)])
        )
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)

        await delegate.pollAndRefresh(monitor)

        XCTAssertEqual(delivery.toasts, [
            Toast(pageName: "GitHub", body: "Major outage", severity: .red)
        ])
    }

    func testPageOverallWithNoComponentsStillDeliversToast() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: directory, pageURL: pageURL)
        let monitor = Monitor(
            store: store,
            client: SequenceHTTPClient(responses: [Data(redWithoutComponentsJSON.utf8)])
        )
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)

        await delegate.pollAndRefresh(monitor)

        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)
        XCTAssertEqual(delivery.toasts, [
            Toast(pageName: "GitHub", body: "Major outage", severity: .red)
        ])
    }

    func testPersistenceErrorsPresentOnceUntilSuccessfulPollResetsGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: directory, pageURL: pageURL)

        let sequence = SequenceHTTPClient(responses: [
            Data(redJSON.utf8),
            Data(redJSON.utf8),
            Data(redJSON.utf8),
            Data(greenJSON.utf8)
        ])
        let monitor = Monitor(store: store, client: sequence)
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        var presentedErrors = 0
        delegate.presentError = { _ in presentedErrors += 1 }

        try breakPersistence(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)
        XCTAssertTrue(delivery.toasts.isEmpty)

        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)
        XCTAssertTrue(delivery.toasts.isEmpty)

        try FileManager.default.removeItem(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
        XCTAssertEqual(try store.load().pages[0].snapshot?.overall, .red)
        XCTAssertEqual(delivery.toasts, [
            Toast(pageName: "GitHub", body: "Major outage", severity: .red)
        ])

        try breakPersistence(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 2)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
        XCTAssertEqual(delivery.toasts.count, 1)
    }

    func testStaleSuccessfulPollDoesNotResetPersistenceErrorGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: directory, pageURL: pageURL)

        let client = ControllableHTTPClient()
        defer { client.failAll() }
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        var presentedErrors = 0
        delegate.presentError = { _ in presentedErrors += 1 }
        let pollA = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(1)
        let pollB = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(2)

        try breakPersistence(at: store.configURL)
        client.complete(request: 2, with: Data(redJSON.utf8))
        await pollB.value
        XCTAssertEqual(presentedErrors, 1)

        client.complete(request: 1, with: Data(redJSON.utf8))
        await pollA.value
        XCTAssertEqual(presentedErrors, 1)

        let pollC = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(3)
        client.complete(request: 3, with: Data(redJSON.utf8))
        await pollC.value
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertTrue(delivery.toasts.isEmpty)
    }

    func testCancelledPollDoesNotPresentAnError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = try await seedStore(at: directory, pageURL: pageURL)
        let client = ControllableHTTPClient()
        defer { client.failAll() }
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate()
        var presentedErrors = 0
        delegate.presentError = { _ in presentedErrors += 1 }

        let poll = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(1)
        poll.cancel()
        client.complete(request: 1, with: Data(redJSON.utf8))
        await poll.value

        XCTAssertEqual(presentedErrors, 0)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)
    }

    private func seedStore(at directory: URL, pageURL: URL) async throws -> PageStore {
        let store = PageStore(directory: directory)
        let seed = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenJSON.utf8), 200)
            ])
        )
        try await seed.add(url: pageURL, name: nil)
        return store
    }

}

private final class SequenceHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Data]

    init(responses: [Data]) {
        self.responses = responses
    }

    func get(_: URL) async throws -> (Data, Int) {
        try nextResponse()
    }

    private func nextResponse() throws -> (Data, Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return (responses.removeFirst(), 200)
    }
}
