import Foundation
import XCTest
import StatusCore
@testable import greendot

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

    func testPersistenceErrorsPresentOnceUntilSuccessfulPollResetsGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = PageStore(directory: directory)
        let seed = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenJSON.utf8), 200)
            ])
        )
        try await seed.add(url: pageURL, name: nil)

        let sequence = SequenceHTTPClient(responses: [
            Data(redJSON.utf8),
            Data(redJSON.utf8),
            Data(redJSON.utf8),
            Data(greenJSON.utf8)
        ])
        let monitor = Monitor(store: store, client: sequence)
        try monitor.load()
        let delegate = AppDelegate()
        var presentedErrors = 0
        delegate.presentError = { _ in presentedErrors += 1 }

        try breakPersistence(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)

        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .green)

        try FileManager.default.removeItem(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
        XCTAssertEqual(try store.load().pages[0].snapshot?.overall, .red)

        try breakPersistence(at: store.configURL)
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(presentedErrors, 2)
        XCTAssertEqual(monitor.pages[0].snapshot?.overall, .red)
    }

    func testStaleSuccessfulPollDoesNotResetPersistenceErrorGate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let store = PageStore(directory: directory)
        let seed = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenJSON.utf8), 200)
            ])
        )
        try await seed.add(url: pageURL, name: nil)

        let client = GatedHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate()
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
    }

    private func breakPersistence(at configURL: URL) throws {
        try? FileManager.default.removeItem(at: configURL)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
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

private final class GatedHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    private var waiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func get(_: URL) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            requestCount += 1
            let request = requestCount
            pending[request] = continuation
            let ready = waiters.filter { requestCount >= $0.minimum }
            waiters.removeAll { requestCount >= $0.minimum }
            lock.unlock()
            ready.forEach { $0.continuation.resume() }
        }
    }

    func waitUntilRequestCount(_ minimum: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if requestCount >= minimum {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((minimum: minimum, continuation: continuation))
                lock.unlock()
            }
        }
    }

    func complete(request: Int, with data: Data) {
        lock.lock()
        let continuation = pending.removeValue(forKey: request)
        lock.unlock()
        continuation?.resume(returning: (data, 200))
    }
}
