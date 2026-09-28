import XCTest
@testable import StatusCore
import TestSupport

final class SaaSPlatformProbeTests: XCTestCase {
    func testStatusioExtractsPageIDAndFetchesAPI() async throws {
        let html = """
        <html><script>var page_id = "5b36dc6502d06804c08349f7";</script>
        <link href="//static.status.io/public/statuspage/js/jquery.min.js">
        """
        let json = """
        {"result":{"status_overall":{"status_code":100},"status":[]}}
        """
        var inner = MapHTTPClient()
        inner.byURL["https://status.gitlab.com"] = (Data(html.utf8), 200)
        inner.byURL["https://api.status.io/1.0/status/5b36dc6502d06804c08349f7"] = (Data(json.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.gitlab.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .statusio)
        XCTAssertEqual(snap.overall, .green)
        let api = "https://api.status.io/1.0/status/5b36dc6502d06804c08349f7"
        XCTAssertTrue(recording.requested.map(\.absoluteString).contains(api))
    }

    func testSlackLandingFetchesCurrent() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://slack-status.com/api/v2.0.0/current"] = (
            Data("{\"status\":\"ok\",\"active_incidents\":[]}".utf8), 200
        )
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://slack-status.com/")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .slack)
        XCTAssertEqual(snap.name, "Slack")
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://slack-status.com/api/v2.0.0/current"
        ])
    }

    func testHerokuLandingFetchesV4() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.heroku.com/api/v4/current-status"] = (
            Data("{\"status\":[{\"system\":\"Apps\",\"status\":\"green\"}],\"incidents\":[],\"scheduled\":[]}".utf8),
            200
        )
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.heroku.com")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .heroku)
        XCTAssertEqual(snap.components.map(\.name), ["Apps"])
    }

    func testGoogleCloudLandingFetchesIncidents() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.cloud.google.com/incidents.json"] = (Data("[]".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.google.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .google)
        XCTAssertEqual(snap.name, "Google Cloud")
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://status.cloud.google.com/incidents.json"
        ])
    }

    func testAppleLandingFetchesSystemStatus() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://www.apple.com/support/systemstatus/data/system_status_en_US.js"] = (
            Data("{\"services\":[]}".utf8), 200
        )
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.apple.com/support/systemstatus/")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .apple)
        XCTAssertEqual(snap.name, "Apple")
        XCTAssertEqual(snap.overall, .green)
    }

    func testIncidentioSkippedOnOtherHosts() async {
        var inner = MapHTTPClient()
        inner.byURL["https://example.com"] = (Data("<html>no</html>".utf8), 200)
        inner.byURL["https://example.com/proxy/status.incident.io"] = (
            Data("{\"summary\":{\"name\":\"nope\",\"ongoing_incidents\":[]}}".utf8), 200
        )
        let recording = RecordingHTTPClient(inner)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://example.com")!,
                client: recording
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertFalse(
            recording.requested.map(\.absoluteString).contains(
                "https://example.com/proxy/status.incident.io"
            )
        )
    }

    func testIncidentioProxy() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.incident.io/proxy/status.incident.io"] = (
            Data("{\"summary\":{\"name\":\"incident.io\",\"ongoing_incidents\":[]}}".utf8), 200
        )
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.incident.io")!,
            client: inner
        )
        XCTAssertEqual(snap.provider, .incidentio)
        XCTAssertEqual(snap.name, "incident.io")
    }

    func testBitBarLandingReadsSmartBearStatuspage() async throws {
        let json = """
        {
          "page": {"name": "Bitbar Testing Cloud", "url": "https://bitbar.status.smartbear.com"},
          "status": {"indicator": "none"},
          "components": [{"id": "broker", "name": "Appium Broker EU", "status": "operational"}],
          "incidents": []
        }
        """
        var inner = MapHTTPClient()
        inner.byURL["https://bitbar.status.smartbear.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.bitbar.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "Bitbar Testing Cloud")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.url, URL(string: "https://status.bitbar.com")!)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://bitbar.status.smartbear.com/api/v2/summary.json"
        ])
    }

    func testClaudeLandingReadsComponentsNotIncidentHistory() async throws {
        let json = """
        {
          "page": {"name": "Claude", "url": "https://status.claude.com"},
          "status": {"indicator": "none"},
          "components": [
            {"id": "claude-ai", "name": "claude.ai", "status": "operational"},
            {"id": "api", "name": "Claude API (api.anthropic.com)", "status": "operational"}
          ],
          "incidents": [{"id": "old", "name": "Elevated errors for multiple models", "status": "resolved"}]
        }
        """
        var inner = MapHTTPClient()
        let incidentFeed = """
        <rss version="2.0"><channel><item><title>Elevated errors for multiple models</title></item></channel></rss>
        """
        inner.byURL["https://status.claude.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        inner.byURL["https://status.claude.com/history.rss"] = (Data(incidentFeed.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.claude.com")!,
            client: recording,
            prefer: .rss
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.components.map(\.name), [
            "claude.ai",
            "Claude API (api.anthropic.com)"
        ])
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://status.claude.com/api/v2/summary.json"
        ])
    }

    func testZoomLandingReadsZoomStatuspage() async throws {
        let json = """
        {
          "page": {"name": "Zoom", "url": "https://www.zoomstatus.com"},
          "status": {"indicator": "none"},
          "components": [{"id": "meetings", "name": "Zoom Meetings", "status": "operational"}],
          "incidents": []
        }
        """
        var inner = MapHTTPClient()
        inner.byURL["https://www.zoomstatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.zoom.us")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "Zoom")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.url, URL(string: "https://status.zoom.us")!)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://www.zoomstatus.com/api/v2/summary.json"
        ])
    }

    func testStripeLandingUsesStatuspageJSON() async throws {
        let json = """
        {
          "page": {"name": "Stripe", "url": "https://www.stripestatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """
        var inner = MapHTTPClient()
        inner.byURL["https://www.stripestatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.stripe.com")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "Stripe")
        XCTAssertEqual(snap.url, URL(string: "https://status.stripe.com")!)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://www.stripestatus.com/api/v2/summary.json"
        ])
    }

    func testGoogleLanding503IsUnreachable() async {
        var inner = MapHTTPClient()
        inner.byURL["https://status.cloud.google.com/incidents.json"] = (Data(), 503)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://status.cloud.google.com")!,
                client: inner
            )
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }
}
