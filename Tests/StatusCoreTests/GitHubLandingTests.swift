import XCTest
@testable import StatusCore
import TestSupport

final class GitHubLandingTests: XCTestCase {
    func testGitHubLandingReadsComponentsNotIncidentHistory() async throws {
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "minor", "description": "Partially Degraded Service"},
          "components": [
            {"id": "br0l2tvcx85d", "name": "Actions", "status": "degraded_performance"},
            {"id": "codespaces", "name": "Codespaces", "status": "operational"}
          ],
          "incidents": [{"id": "2dpbcq5j165n", "name": "Actions Job Delays", "status": "investigating"}]
        }
        """
        let html = """
        <html><head>
        <link rel="alternate" type="application/atom+xml" href="/history.atom">
        </head></html>
        """
        let history = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>GitHub Status - Incident History</title>
          <entry><title>Actions Job Delays</title><id>tag:history</id></entry>
        </feed>
        """
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        inner.byURL["https://www.githubstatus.com"] = (Data(html.utf8), 200)
        inner.byURL["https://www.githubstatus.com/history.atom"] = (Data(history.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: recording,
            prefer: .rss
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components.map(\.name), ["Actions", "Codespaces"])
        XCTAssertEqual(snap.components.first { $0.name == "Actions" }?.severity, .yellow)
        XCTAssertEqual(snap.incidents.map(\.title), ["Actions Job Delays"])
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://www.githubstatus.com/api/v2/summary.json"
        ])
    }
}
