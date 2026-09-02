import XCTest
@testable import StatusCore
import TestSupport

final class RssHtmlDiscoveryTests: XCTestCase {
    private let feed = """
    <rss version="2.0"><channel><title>Secret Feed</title>
    <item><guid>item-1</guid><title>API</title><status>Available</status></item>
    </channel></rss>
    """

    func testProbeIgnoresNotRssMimeSubstring() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/notrss+xml" href="/old.xml">
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

    func testProbeReadsAlternateLinkWithGreaterThanInQuotedTitle() async throws {
        let html = """
        <html><head>
        <link rel="alternate" title="Status > Incidents" type="application/rss+xml" href="/feed.xml">
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

    func testProbeSkipsAlternateLinksInsideNestedTemplates() async throws {
        let html = """
        <html><head>
        <template><template></template><link rel="alternate" type="application/rss+xml" href="/old.xml"></template>
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

    func testProbeSkipsAlternateLinksInsideTextarea() async throws {
        let html = """
        <html><head>
        <textarea><link rel="alternate" type="application/rss+xml" href="/old.xml"></textarea>
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

    func testProbeSkipsUnclosedQuotedLinkAndFindsLaterAlternate() async throws {
        let html = """
        <html><head>
        <link rel="stylesheet" href="/broken.css" title="unterminated
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
}
