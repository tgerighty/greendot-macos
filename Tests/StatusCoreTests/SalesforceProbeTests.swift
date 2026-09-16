import XCTest
@testable import StatusCore
import TestSupport

final class SalesforceProbeTests: XCTestCase {
    private let landing = "https://status.salesforce.com"
    private let activeURL = "https://api.status.salesforce.com/v1/incidents/active"
    private let emptyJSON = Data("[]".utf8)

    func testLandingFetchesOnlyActiveIncidents() async throws {
        for page in [landing, landing + "/"] {
            var inner = activeClient()
            inner.byURL[page] = (Data("<html>spa</html>".utf8), 200)
            inner.byURL[page + "/api/v2/summary.json"] = (Data("{}".utf8), 200)
            let recording = RecordingHTTPClient(inner)
            let snap = try await ProviderProbe.probe(pageURL: URL(string: page)!, client: recording)
            XCTAssertEqual(snap.provider, .salesforce, page)
            XCTAssertEqual(snap.name, "Salesforce", page)
            XCTAssertEqual(snap.url, URL(string: landing)!, page)
            XCTAssertEqual(snap.overall, .green, page)
            XCTAssertTrue(snap.components.isEmpty, page)
            XCTAssertTrue(snap.incidents.isEmpty, page)
            XCTAssertEqual(recording.requested.map(\.absoluteString), [activeURL], page)
        }
    }

    func testProductPathIsNotLanding() async {
        var inner = activeClient()
        inner.byURL["https://status.salesforce.com/products/Tableau"] = (Data("<html>spa</html>".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://status.salesforce.com/products/Tableau")!,
                client: recording
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertFalse(recording.requested.map(\.absoluteString).contains(activeURL))
    }

    func testNonSalesforceHostDoesNotUseSalesforceParser() async {
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com"] = (Data("<html>no</html>".utf8), 200)
        inner.byURL[activeURL] = (emptyJSON, 200)
        let recording = RecordingHTTPClient(inner)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://www.githubstatus.com")!,
                client: recording
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertFalse(recording.requested.map(\.absoluteString).contains(activeURL))
    }

    func testPreferSalesforceOnLandingFetchesOnlyActiveIncidents() async throws {
        var inner = activeClient()
        inner.byURL["https://status.salesforce.com/api/v2/summary.json"] = (Data("{}".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: landing)!,
            client: recording,
            prefer: .salesforce
        )
        XCTAssertEqual(snap.provider, .salesforce)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [activeURL])
    }

    func testPreferSalesforceOnNonLandingDoesNotGetActiveIncidents() async throws {
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        inner.byURL[activeURL] = (emptyJSON, 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: recording,
            prefer: .salesforce
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertFalse(recording.requested.map(\.absoluteString).contains(activeURL))
    }

    func testUnchangedBodySkipsParse() async throws {
        let client = activeClient()
        let page = URL(string: landing)!
        ProviderProbe.resetCounts()
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .salesforce)
        XCTAssertEqual(first.body, Data("HTTP 200\n".utf8) + emptyJSON)
        XCTAssertGreaterThan(ProviderProbe.parseCount, 0)
        ProviderProbe.resetCounts()
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .salesforce,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(ProviderProbe.parseCount, 0)
        XCTAssertEqual(second.snapshot, first.snapshot)
    }

    func testActiveIncidents503IsUnreachable() async {
        let recording = RecordingHTTPClient(activeClient(status: 503, body: Data()))
        do {
            _ = try await ProviderProbe.probe(pageURL: URL(string: landing)!, client: recording)
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [activeURL])
    }

    func testActiveIncidentsHTMLIsUnsupported() async {
        let recording = RecordingHTTPClient(activeClient(body: Data("<html>no</html>".utf8)))
        do {
            _ = try await ProviderProbe.probe(pageURL: URL(string: landing)!, client: recording)
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [activeURL])
    }

    func testLandingMissDoesNotFallThroughToStatuspage() async {
        var inner = activeClient(status: 404, body: Data())
        inner.byURL["https://status.salesforce.com/api/v2/summary.json"] = (
            Data("""
            {
              "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
              "status": {"indicator": "none"},
              "components": [],
              "incidents": []
            }
            """.utf8),
            200
        )
        let recording = RecordingHTTPClient(inner)
        do {
            _ = try await ProviderProbe.probe(pageURL: URL(string: landing)!, client: recording)
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [activeURL])
    }

    private func activeClient(status: Int = 200, body: Data? = nil) -> MapHTTPClient {
        var client = MapHTTPClient()
        client.byURL[activeURL] = (body ?? emptyJSON, status)
        return client
    }
}
