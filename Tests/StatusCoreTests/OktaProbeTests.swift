import XCTest
@testable import StatusCore
import TestSupport

final class OktaProbeTests: XCTestCase {
    private let landing = "https://status.okta.com"
    private let html = """
    <html><body>
    <span data-id="incidents">[]</span>
    <span data-id="planned-outages">[]</span>
    </body></html>
    """

    func testOktaLandingFetchesHTMLOnly() async throws {
        for page in [landing, landing + "/", landing + ""] {
            var inner = MapHTTPClient()
            inner.byURL[landing] = (Data(html.utf8), 200)
            inner.byURL[landing + "/"] = (Data(html.utf8), 200)
            inner.byPath["/"] = (Data(html.utf8), 200)
            inner.byPath["/api/v2/summary.json"] = (Data("{}".utf8), 200)
            let recording = RecordingHTTPClient(inner)
            let snap = try await ProviderProbe.probe(pageURL: URL(string: page)!, client: recording)
            XCTAssertEqual(snap.provider, .okta, page)
            XCTAssertEqual(snap.name, "Okta", page)
            XCTAssertEqual(snap.url, URL(string: landing)!, page)
            XCTAssertEqual(snap.overall, .green, page)
            XCTAssertTrue(snap.components.isEmpty, page)
            XCTAssertFalse(recording.requested.contains { $0.path.contains("summary.json") }, page)
            XCTAssertTrue(recording.requested.contains { $0.host == "status.okta.com" }, page)
        }
    }

    func testNonOktaHostDoesNotUseOktaParser() async {
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com"] = (Data(html.utf8), 200)
        inner.byPath["/"] = (Data(html.utf8), 200)
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
        XCTAssertFalse(recording.requested.contains { $0.host == "status.okta.com" })
    }

    func testPreferOktaSkipsJSONProviders() async throws {
        var inner = MapHTTPClient()
        inner.byURL[landing] = (Data(html.utf8), 200)
        inner.byPath["/"] = (Data(html.utf8), 200)
        inner.byPath["/api/v2/summary.json"] = (Data("{}".utf8), 200)
        inner.byPath["/summary.json"] = (Data("{}".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: landing)!,
            client: recording,
            prefer: .okta
        )
        XCTAssertEqual(snap.provider, .okta)
        XCTAssertEqual(recording.requested.map(\.host), ["status.okta.com"])
        XCTAssertFalse(recording.requested.contains { $0.path.contains("summary") })
    }

    func testUnreachableOnOkta500() async {
        var inner = MapHTTPClient()
        inner.byURL[landing] = (Data(), 500)
        inner.byPath["/"] = (Data(), 500)
        do {
            _ = try await ProviderProbe.probe(pageURL: URL(string: landing)!, client: inner)
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    func testUnchangedHTMLSkipsParse() async throws {
        var inner = MapHTTPClient()
        inner.byURL[landing] = (Data(html.utf8), 200)
        inner.byPath["/"] = (Data(html.utf8), 200)
        let page = URL(string: landing)!
        let first = try await ProviderProbe.probeHit(pageURL: page, client: inner, prefer: .okta)
        ProviderProbe.resetCounts()
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: inner,
            prefer: .okta,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(second.snapshot, first.snapshot)
        XCTAssertEqual(ProviderProbe.parseCount, 0)
    }
}
