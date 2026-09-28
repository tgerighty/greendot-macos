import XCTest
@testable import StatusCore

final class RateLimitGateTests: XCTestCase {
    private let macURL = URL(string: "https://status.cloud.microsoft/api/feed/mac")!
    private let ppacURL = URL(string: "https://status.cloud.microsoft/api/feed/ppac")!
    private let azureURL = URL(string: "https://rssfeed.azure.status.microsoft/en-us/status/feed/")!
    private let macFeed = """
    <rss version="2.0"><channel><title>Microsoft Admin Center Status</title>
    <item><guid>mac-1</guid><title>Microsoft Admin Center</title><status>Available</status></item>
    </channel></rss>
    """
    private let ppacFeed = """
    <rss version="2.0"><channel><title>Power Platform Admin Center Status</title>
    <item><guid>ppac-1</guid><title>Power Platform Admin Center</title><status>Available</status></item>
    </channel></rss>
    """
    private let azureFeed = """
    <rss version="2.0"><channel><title>Azure Status</title></channel></rss>
    """

    override func tearDown() {
        ScriptedHTTP.reset()
        super.tearDown()
    }

    func testRetryAfterSecondsAreCappedAndBlankUsesSixty() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RetryAfterDelay.seconds(from: nil, now: now), 60)
        XCTAssertEqual(RetryAfterDelay.seconds(from: "  ", now: now), 60)
        XCTAssertEqual(RetryAfterDelay.seconds(from: "nope", now: now), 60)
        XCTAssertEqual(RetryAfterDelay.seconds(from: "0", now: now), 0)
        XCTAssertEqual(RetryAfterDelay.seconds(from: "60", now: now), 60)
        XCTAssertEqual(RetryAfterDelay.seconds(from: "9999", now: now), 300)
    }

    func testRetryAfterHTTPDateIsADelayFromNow() {
        let now = Date(timeIntervalSince1970: 1_000)
        let later = now.addingTimeInterval(90)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: later)
        XCTAssertEqual(RetryAfterDelay.seconds(from: header, now: now), 90)
        XCTAssertEqual(RetryAfterDelay.seconds(from: formatter.string(from: now), now: now), 0)
    }

    func test429ReplaysTheLastSmallSuccessUntilTheWaitEnds() {
        var now = Date(timeIntervalSince1970: 1_000)
        let gate = RateLimitGate()
        gate.now = { now }
        let url = URL(string: "https://backoff.test/feed")!
        let body = Data("feed".utf8)
        let success = HTTPGet(data: body, status: 200, url: url)
        XCTAssertEqual(gate.receive(url, response: success, retryAfter: nil).status, 200)
        let limited = HTTPGet(data: Data(), status: 429, url: url)
        let replay = gate.receive(url, response: limited, retryAfter: "60")
        XCTAssertEqual(replay.status, 200)
        XCTAssertEqual(replay.data, body)
        XCTAssertEqual(gate.cached(url)?.data, body)
        now = now.addingTimeInterval(60)
        XCTAssertNil(gate.cached(url))
    }

    func test429WithNoHistoryStaysLimitedWithoutExtendingOnAHeldRead() {
        var now = Date(timeIntervalSince1970: 1_000)
        let gate = RateLimitGate()
        gate.now = { now }
        let url = URL(string: "https://backoff.test/feed")!
        let limited = HTTPGet(data: Data(), status: 429, url: url)
        XCTAssertEqual(gate.receive(url, response: limited, retryAfter: "60").status, 429)
        XCTAssertEqual(gate.cached(url)?.status, 429)
        now = now.addingTimeInterval(59)
        XCTAssertEqual(gate.cached(url)?.status, 429)
        now = now.addingTimeInterval(1)
        XCTAssertNil(gate.cached(url))
    }

    func testServerErrorDoesNotStartTheWaitOrReplay() {
        let gate = RateLimitGate()
        let url = URL(string: "https://backoff.test/feed")!
        let success = HTTPGet(data: Data("ok".utf8), status: 200, url: url)
        _ = gate.receive(url, response: success, retryAfter: nil)
        let failed = HTTPGet(data: Data(), status: 503, url: url)
        XCTAssertEqual(gate.receive(url, response: failed, retryAfter: "60").status, 503)
        XCTAssertNil(gate.cached(url))
    }

    func testOversizedSuccessIsNotReplayed() {
        let gate = RateLimitGate()
        let url = URL(string: "https://backoff.test/feed")!
        let success = HTTPGet(data: Data(count: RateLimitGate.maxCachedBytes + 1), status: 200, url: url)
        _ = gate.receive(url, response: success, retryAfter: nil)
        let limited = HTTPGet(data: Data(), status: 429, url: url)
        XCTAssertEqual(gate.receive(url, response: limited, retryAfter: "60").status, 429)
    }

    func testClientDoesNotRepeatALimitedURLUntilTheWaitEnds() async throws {
        let url = URL(string: "https://backoff.test/feed")!
        ScriptedHTTP.serve(host: "backoff.test", url: url.absoluteString, items: [
            ScriptedHTTP.Item(status: 200, headers: [:], body: Data("ok".utf8)),
            ScriptedHTTP.Item(status: 429, headers: ["Retry-After": "60"], body: Data()),
            ScriptedHTTP.Item(status: 200, headers: [:], body: Data("next".utf8))
        ])
        let client = scriptedClient()
        var now = Date(timeIntervalSince1970: 5_000)
        client.rateLimit.now = { now }

        let first = try await client.get(url)
        XCTAssertEqual(first.0, Data("ok".utf8))
        XCTAssertEqual(first.1, 200)
        let second = try await client.get(url)
        XCTAssertEqual(second.0, Data("ok".utf8))
        XCTAssertEqual(second.1, 200)
        let third = try await client.get(url)
        XCTAssertEqual(third.0, Data("ok".utf8))
        XCTAssertEqual(ScriptedHTTP.hitCount(url.absoluteString), 2)

        now = now.addingTimeInterval(61)
        let fourth = try await client.get(url)
        XCTAssertEqual(fourth.0, Data("next".utf8))
        XCTAssertEqual(fourth.1, 200)
        XCTAssertEqual(ScriptedHTTP.hitCount(url.absoluteString), 3)
    }

    func testMicrosoftHubKeepsTheLastReadingWhenTheFeedIsLimited() async throws {
        let page = URL(string: "https://status.cloud.microsoft/")!
        ScriptedHTTP.serve(host: "status.cloud.microsoft", url: macURL.absoluteString, items: [
            ScriptedHTTP.Item(status: 200, headers: [:], body: Data(macFeed.utf8)),
            ScriptedHTTP.Item(status: 429, headers: ["Retry-After": "60"], body: Data()),
            ScriptedHTTP.Item(status: 200, headers: [:], body: Data(macFeed.utf8))
        ])
        ScriptedHTTP.serve(
            host: "status.cloud.microsoft",
            url: ppacURL.absoluteString,
            items: Array(repeating: ScriptedHTTP.Item(status: 200, headers: [:], body: Data(ppacFeed.utf8)), count: 4)
        )
        ScriptedHTTP.serve(
            host: "rssfeed.azure.status.microsoft",
            url: azureURL.absoluteString,
            items: Array(repeating: ScriptedHTTP.Item(status: 200, headers: [:], body: Data(azureFeed.utf8)), count: 4)
        )
        let client = scriptedClient()
        var now = Date(timeIntervalSince1970: 5_000)
        client.rateLimit.now = { now }

        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .rss)
        XCTAssertEqual(first.snapshot.components[0].severity, .green)
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .rss,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(second.snapshot.components[0].severity, .green)
        let third = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .rss,
            previousBody: second.body,
            previousSnapshot: second.snapshot
        )
        XCTAssertEqual(third.snapshot.components[0].severity, .green)
        XCTAssertEqual(ScriptedHTTP.hitCount(macURL.absoluteString), 2)

        now = now.addingTimeInterval(61)
        _ = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .rss,
            previousBody: third.body,
            previousSnapshot: third.snapshot
        )
        XCTAssertEqual(ScriptedHTTP.hitCount(macURL.absoluteString), 3)
    }

    private func scriptedClient() -> URLSessionHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScriptedHTTP.self]
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSessionHTTPClient(session: URLSession(configuration: config))
    }
}

private final class ScriptedHTTP: URLProtocol, @unchecked Sendable {
    struct Item {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private static var hosts: Set<String> = []
    private static var queue: [String: [Item]] = [:]
    private static var hits: [String: Int] = [:]

    static func reset() {
        lock.lock()
        hosts = []
        queue = [:]
        hits = [:]
        lock.unlock()
    }

    static func serve(host: String, url: String, items: [Item]) {
        lock.lock()
        hosts.insert(host)
        queue[url] = items
        if hits[url] == nil { hits[url] = 0 }
        lock.unlock()
    }

    static func hitCount(_ url: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return hits[url] ?? 0
    }

    override static func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        lock.lock()
        defer { lock.unlock() }
        return hosts.contains(host)
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        let key = url.absoluteString
        ScriptedHTTP.lock.lock()
        ScriptedHTTP.hits[key, default: 0] += 1
        var items = ScriptedHTTP.queue[key] ?? []
        let item = items.isEmpty ? nil : items.removeFirst()
        ScriptedHTTP.queue[key] = items
        ScriptedHTTP.lock.unlock()
        guard let item else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: item.status,
            httpVersion: "HTTP/1.1",
            headerFields: item.headers
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: item.body)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
