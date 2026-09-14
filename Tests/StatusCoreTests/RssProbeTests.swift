import XCTest
@testable import StatusCore
import TestSupport

final class RssProbeTests: XCTestCase {
    private let macFeed = """
    <rss version="2.0">
      <channel>
        <title>Microsoft Admin Center Status</title>
        <link>https://status.cloud.microsoft/</link>
        <item>
          <guid>mac-1</guid>
          <title>Microsoft Admin Center</title>
          <status>ServiceDegradation</status>
        </item>
      </channel>
    </rss>
    """

    private let ppacFeed = """
    <rss version="2.0">
      <channel>
        <title>Power Platform Admin Center Status</title>
        <link>https://status.cloud.microsoft/</link>
        <item>
          <guid>ppac-1</guid>
          <title>Power Platform Admin Center</title>
          <status>Available</status>
        </item>
      </channel>
    </rss>
    """

    private let azureFeed = """
    <rss version="2.0">
      <channel>
        <title>Azure Status</title>
        <link>https://azure.status.microsoft/en-us/status/</link>
      </channel>
    </rss>
    """

    func testProbeReadsRSSFeedURL() async throws {
        var client = MapHTTPClient()
        let page = URL(string: "https://status.example.com/feed.xml")!
        client.byURL[page.absoluteString] = (Data(macFeed.utf8), 200)
        let snap = try await ProviderProbe.probe(pageURL: page, client: client)
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Microsoft Admin Center Status")
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components.map(\.name), ["Microsoft Admin Center"])
    }

    func testProbePreservesQueryOnDirectFeedURL() async throws {
        var inner = MapHTTPClient()
        let page = URL(string: "https://status.example.com/feed.xml?token=secret")!
        inner.byURL[page.absoluteString] = (Data(macFeed.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(pageURL: page, client: recording)
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertTrue(recording.requested.map(\.absoluteString).contains(page.absoluteString))
    }

    func testProbeRejectsCrossOriginAlternateFeed() async {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="https://evil.example/feed.xml">
        </head></html>
        """
        var client = MapHTTPClient()
        client.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        client.byURL["https://evil.example/feed.xml"] = (Data(macFeed.utf8), 200)
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

    func testProbeFollowsHTMLAlternateLink() async throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="/feed.xml">
        </head><body>hello</body></html>
        """
        var client = MapHTTPClient()
        client.byURL["https://status.example.com"] = (Data(html.utf8), 200)
        client.byURL["https://status.example.com/feed.xml"] = (Data(macFeed.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.example.com")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.components.first?.id, "mac-1")
    }

    func testMicrosoftLandingIsOnePageWithThreeGroups() async throws {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft/")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Microsoft")
        XCTAssertEqual(snap.url, URL(string: "https://status.cloud.microsoft")!)
        XCTAssertEqual(snap.components.map(\.id), ["m365", "ppac", "azure"])
        XCTAssertEqual(snap.components.map(\.name), ["Microsoft 365", "Power Platform", "Azure"])
        XCTAssertTrue(snap.components.allSatisfy(\.isGroup))
        XCTAssertEqual(snap.components[0].children.map(\.name), ["Microsoft Admin Center"])
        XCTAssertEqual(snap.components[0].children.first?.severity, .yellow)
        XCTAssertEqual(snap.components[1].children.first?.severity, .green)
        XCTAssertTrue(snap.components[2].children.isEmpty)
        XCTAssertEqual(snap.components[2].severity, .green)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertTrue(snap.incidents.isEmpty)
    }

    func testMicrosoftFeedPathIsFlatNotHub() async throws {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft/api/feed/mac")!,
            client: client
        )
        XCTAssertEqual(snap.name, "Microsoft Admin Center Status")
        XCTAssertEqual(snap.components.map(\.name), ["Microsoft Admin Center"])
        XCTAssertFalse(snap.components[0].isGroup)
    }

    func testStatuspageWinsWhenRSSAlsoExists() async throws {
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """
        var client = MapHTTPClient()
        client.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        client.byURL["https://www.githubstatus.com"] = (Data(macFeed.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "GitHub")
    }

    func testPreferRSSOnMicrosoftLandingFetchesOnlyHubFeeds() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        inner.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        inner.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft/")!,
            client: recording,
            prefer: .rss
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://status.cloud.microsoft/api/feed/mac",
            "https://status.cloud.microsoft/api/feed/ppac",
            "https://rssfeed.azure.status.microsoft/en-us/status/feed/"
        ])
    }

    func testHubPartialFailureGreysThatGroup() async throws {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(), 503)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft/")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.components[2].id, "azure")
        XCTAssertEqual(snap.components[2].severity, .grey)
        XCTAssertEqual(snap.components[2].statusText, "Unreachable")
        XCTAssertTrue(snap.components[2].children.isEmpty)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertFalse(snap.isUnreachable)
    }

    func testHubAllFeedsDownIsUnreachable() async {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(), 503)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(), 503)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(), 503)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://status.cloud.microsoft/")!,
                client: client,
                prefer: .rss
            )
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    func testUnknownHTMLWithoutAlternateIsUnsupported() async {
        var client = MapHTTPClient()
        client.byURL["https://example.com"] = (Data("<html><body>no feed</body></html>".utf8), 200)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://example.com")!,
                client: client
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
    }

    func testUnsupportedErrorNamesRSS() {
        XCTAssertEqual(
            ProbeError.unsupported.errorDescription,
            "This URL is not a known status page format (Statuspage, Statuspal, Instatus, Flashduty, AWS, Icinga, Okta, or RSS/Atom)."
        )
    }

    func testDoesNotTreatFeedbackTagAsFeed() async {
        var client = MapHTTPClient()
        client.byURL["https://example.com"] = (Data("<html><body><feedback>no</feedback></body></html>".utf8), 200)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://example.com")!,
                client: client
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
    }

    func testMonitorAddMicrosoftLandingStoresOnePage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 200)
        let monitor = Monitor(store: PageStore(directory: dir), client: client)
        try await monitor.add(url: URL(string: "https://status.cloud.microsoft/")!, name: nil)
        XCTAssertEqual(monitor.pages.count, 1)
        XCTAssertEqual(monitor.pages[0].name, "Microsoft")
        XCTAssertEqual(monitor.pages[0].url, URL(string: "https://status.cloud.microsoft/")!)
        XCTAssertEqual(monitor.pages[0].snapshot?.components.count, 3)
    }
}
