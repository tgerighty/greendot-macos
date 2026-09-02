import XCTest
@testable import StatusCore
import TestSupport

final class RssPersistTests: XCTestCase {
    private let feed = """
    <rss version="2.0">
      <channel>
        <title>Secret Feed</title>
        <item>
          <guid>item-1</guid>
          <title>API</title>
          <status>Available</status>
        </item>
      </channel>
    </rss>
    """

    func testMonitorAddKeepsFeedQueryForLaterPolls() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let page = URL(string: "https://status.example.com/feed.xml?token=secret")!
        var client = MapHTTPClient()
        client.byURL[page.absoluteString] = (Data(feed.utf8), 200)
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try await monitor.add(url: page, name: nil)
        XCTAssertEqual(monitor.pages[0].url, page)

        let toasts = try await monitor.pollAll()
        XCTAssertTrue(toasts.isEmpty)
        XCTAssertEqual(monitor.pages[0].url, page)
        XCTAssertEqual(monitor.pages[0].snapshot?.provider, .rss)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)
    }

    func testMonitorEditKeepsFeedQuery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = URL(string: "https://status.example.com/feed.xml")!
        let edited = URL(string: "https://status.example.com/feed.xml?token=secret")!
        var client = MapHTTPClient()
        client.byURL[original.absoluteString] = (Data(feed.utf8), 200)
        client.byURL[edited.absoluteString] = (Data(feed.utf8), 200)
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try await monitor.add(url: original, name: nil)
        try await monitor.edit(id: monitor.pages[0].id, url: edited, name: nil)
        XCTAssertEqual(monitor.pages[0].url, edited)
    }

    func testPersistedPageURLAddsHTTPSAuthorityForSchemeLessInput() {
        let input = URL(string: "status.example.com/feed.xml?token=x#section")!
        XCTAssertEqual(
            ProviderProbe.persistedPageURL(input).absoluteString,
            "https://status.example.com/feed.xml?token=x"
        )
    }

    func testProbeSkipsCommentedOutAlternateLink() async throws {
        let html = """
        <html><head>
        <!-- <link rel="alternate" type="application/rss+xml" href="/old.xml"> -->
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/old.xml"] = (Data("<html>old</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/old.xml")
        )
    }

    func testProbeSkipsAlternateLinksInsideScriptAndStyle() async throws {
        let html = """
        <html><head>
        <script>const html = '<link rel="alternate" type="application/rss+xml" href="/old.xml">';</script>
        <style>/* <link rel="alternate" type="application/rss+xml" href="/css.xml"> */</style>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/old.xml"] = (Data("<html>old</html>".utf8), 200)
        inner.byURL["https://status.example.com/css.xml"] = (Data("<html>css</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/old.xml")
        )
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/css.xml")
        )
    }

    func testProbeIgnoresHrefTextInsideQuotedAttributeValues() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="Feed href=/wrong.xml label" href="/feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/wrong.xml"] = (Data("<html>wrong</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/wrong.xml")
        )
    }

    func testProbeDecodesNumericHTMLEntitiesInAlternateHref() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml?format=rss&#38;token=secret">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml?format=rss&token=secret"] = (Data(feed.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertTrue(
            recording.requested.map(\.absoluteString)
                .contains("https://status.example.com/feed.xml?format=rss&token=secret")
        )
    }

    func testProbeIgnoresDataHrefAndReadsUnquotedHref() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" data-href="/wrong.xml">
        <link rel=alternate type=application/rss+xml href=/feed.xml>
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/wrong.xml"] = (Data("<html>wrong</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertTrue(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/feed.xml")
        )
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://status.example.com/wrong.xml")
        )
    }

    func testProbeDecodesHTMLEntitiesInAlternateHref() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml?format=rss&amp;token=secret">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml?format=rss&token=secret"] = (Data(feed.utf8), 200)
        inner.byURL["https://status.example.com/feed.xml?format=rss&amp;token=secret"] = (
            Data("<html>encoded</html>".utf8), 200
        )
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertTrue(
            recording.requested.map(\.absoluteString)
                .contains("https://status.example.com/feed.xml?format=rss&token=secret")
        )
        XCTAssertFalse(
            recording.requested.map(\.absoluteString)
                .contains("https://status.example.com/feed.xml?format=rss&amp;token=secret")
        )
    }

    func testProbeResolvesDirectoryRelativeAlternateAgainstPageURL() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="feed.xml">
        </head></html>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://example.com/status/"] = (Data(html.utf8), 200)
        inner.byURL["https://example.com/status/feed.xml"] = (Data(feed.utf8), 200)
        inner.byURL["https://example.com/feed.xml"] = (Data("<html>wrong</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://example.com/status/")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Secret Feed")
        XCTAssertTrue(
            recording.requested.map(\.absoluteString).contains("https://example.com/status/feed.xml")
        )
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains("https://example.com/feed.xml")
        )
    }
}
