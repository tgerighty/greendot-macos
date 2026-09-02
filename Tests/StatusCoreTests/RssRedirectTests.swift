import XCTest
@testable import StatusCore
import TestSupport

final class RssRedirectTests: XCTestCase {
    private let feed = """
    <rss version="2.0"><channel><title>Secret Feed</title>
    <item><guid>item-1</guid><title>API</title><status>Available</status></item>
    </channel></rss>
    """

    func testProbeRejectsCrossOriginRedirectForFeedDiscovery() async {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="https://evil.example/feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://evil.example/feed.xml"] = (Data(feed.utf8), 200)
        let client = LocatedHTTPClient(
            inner: inner,
            located: [
                "https://status.example.com": URL(string: "https://evil.example/")!
            ]
        )
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://status.example.com")!,
                client: client
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
    }

    func testSameHostRedirectPolicy() {
        let from = URL(string: "https://status.example.com/old")!
        XCTAssertTrue(
            RedirectPolicy.allows(
                URLRequest(url: URL(string: "https://status.example.com/status/")!),
                from: from
            )
        )
        XCTAssertFalse(
            RedirectPolicy.allows(
                URLRequest(url: URL(string: "https://evil.example/status/")!),
                from: from
            )
        )
        XCTAssertFalse(
            RedirectPolicy.allows(
                URLRequest(url: URL(string: "http://status.example.com/old")!),
                from: from
            )
        )
        XCTAssertFalse(
            RedirectPolicy.allows(
                URLRequest(url: URL(string: "https://status.example.com:8443/old")!),
                from: from
            )
        )
        XCTAssertTrue(
            RedirectPolicy.allows(
                URLRequest(url: URL(string: "https://status.example.com/old")!),
                from: URL(string: "http://status.example.com/old")!
            )
        )
        XCTAssertFalse(
            ProviderProbe.isAllowedFeedURL(
                URL(string: "http://status.example.com/feed.xml")!,
                relativeTo: URL(string: "https://status.example.com/")!
            )
        )
        XCTAssertFalse(
            ProviderProbe.isAllowedFeedURL(
                URL(string: "https://status.example.com:8443/feed.xml")!,
                relativeTo: URL(string: "https://status.example.com/")!
            )
        )
        XCTAssertTrue(
            ProviderProbe.isAllowedFeedURL(
                URL(string: "https://status.example.com/feed.xml")!,
                relativeTo: URL(string: "http://status.example.com/")!
            )
        )
    }

    func testRedirectDelegateRejectsHTTPDowngradeAfterHTTPSUpgrade() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let original = URL(string: "http://status.example.com/old")!
        let task = session.dataTask(with: original)
        let https = URL(string: "https://status.example.com/old")!
        let response = HTTPURLResponse(
            url: https,
            statusCode: 301,
            httpVersion: nil,
            headerFields: ["Location": original.absoluteString]
        )!
        let decided = expectation(description: "redirect decision")
        var allowed: URLRequest?
        SameOriginRedirectDelegate().urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: original)
        ) { request in
            allowed = request
            decided.fulfill()
        }
        wait(for: [decided], timeout: 1)
        XCTAssertNil(allowed)
    }

    func testFeedCacheDoesNotReuseSnapshotWhenLocatedURLChanges() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        let page = URL(string: "https://status.example.com/feed.xml")!
        let first = try await ProviderProbe.probeHit(
            pageURL: page,
            client: LocatedHTTPClient(inner: inner, located: [:]),
            prefer: .rss
        )
        XCTAssertEqual(first.snapshot.url, page)
        let relocated = URL(string: "https://status.example.com/v2/feed.xml")!
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: LocatedHTTPClient(inner: inner, located: [page.absoluteString: relocated]),
            prefer: .rss,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(second.snapshot.url, relocated)
    }

    func testProbeContinuesToAlternateWhenPrefixLooksLikeFeedButDoesNotParse() async throws {
        let html = """
        <html><head>
        <!-- <rss version="2.0"><channel></channel></rss> -->
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Secret Feed")
    }

    func testProbeResolvesAlternateFeedsAgainstRedirectedURL() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com/old"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/status/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data("<html>wrong</html>".utf8), 200)
        let client = LocatedHTTPClient(
            inner: inner,
            located: [
                "https://status.example.com/old": URL(string: "https://status.example.com/status/")!
            ]
        )
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com/old")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Secret Feed")
    }
}

private struct LocatedHTTPClient: HTTPClient {
    let inner: MapHTTPClient
    let located: [String: URL]

    func get(_ url: URL) async throws -> (Data, Int) {
        try await inner.get(url)
    }

    func getLocated(_ url: URL) async throws -> HTTPGet {
        let (data, status) = try await inner.get(url)
        return HTTPGet(data: data, status: status, url: located[url.absoluteString] ?? url)
    }
}
