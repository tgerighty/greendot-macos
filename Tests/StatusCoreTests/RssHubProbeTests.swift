import XCTest
@testable import StatusCore
import TestSupport

final class RssHubProbeTests: XCTestCase {
    private let macFeed = """
    <rss version="2.0"><channel><title>Microsoft Admin Center Status</title>
    <item><guid>mac-1</guid><title>Microsoft Admin Center</title><status>ServiceDegradation</status></item>
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

    func testMicrosoftHubAzureIncidentWithoutStatusIsYellow() async throws {
        let azureIncident = """
        <rss version="2.0"><channel><title>Azure Status</title>
        <item><title>West Europe Storage</title></item></channel></rss>
        """
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureIncident.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft/")!,
            client: client
        )
        XCTAssertEqual(snap.components[2].id, "azure")
        XCTAssertEqual(snap.components[2].severity, .yellow)
        XCTAssertEqual(snap.components[2].children.first?.severity, .yellow)
        XCTAssertEqual(snap.overall, .yellow)
    }

    func testHubStatusChangeWithSameBytesDoesNotReuseSnapshot() async throws {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 200)
        let page = URL(string: "https://status.cloud.microsoft/")!
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .rss)
        XCTAssertEqual(first.snapshot.components[2].severity, .green)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 503)
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .rss,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(second.snapshot.components[2].severity, .grey)
    }

    func testUnchangedMicrosoftHubSkipsParse() async throws {
        var client = MapHTTPClient()
        client.byURL["https://status.cloud.microsoft/api/feed/mac"] = (Data(macFeed.utf8), 200)
        client.byURL["https://status.cloud.microsoft/api/feed/ppac"] = (Data(ppacFeed.utf8), 200)
        client.byURL["https://rssfeed.azure.status.microsoft/en-us/status/feed/"] = (Data(azureFeed.utf8), 200)
        let page = URL(string: "https://status.cloud.microsoft/")!
        ProviderProbe.resetCounts()
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .rss)
        XCTAssertGreaterThan(ProviderProbe.parseCount, 0)
        ProviderProbe.resetCounts()
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .rss,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(ProviderProbe.parseCount, 0)
        XCTAssertEqual(second.snapshot, first.snapshot)
    }
}
