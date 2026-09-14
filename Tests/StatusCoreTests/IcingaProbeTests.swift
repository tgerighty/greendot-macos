import XCTest
@testable import StatusCore
import TestSupport

final class IcingaProbeTests: XCTestCase {
    private let page = URL(string: "https://tg_alert_monitor:s3cret@icinga.example:5665/v1")!
    private let hostsJSON = Data("""
    {"results":[{"attrs":{"name":"web-1","display_name":"Web 1","state":0.0,"downtime_depth":0.0}}]}
    """.utf8)
    private let servicesJSON = Data("""
    {"results":[{"attrs":{"name":"http","display_name":"HTTP","host_name":"web-1","__name":"web-1!http","state":0.0,"downtime_depth":0.0}}]}
    """.utf8)

    func testIcingaAPIFetchesHostsAndServices() async throws {
        let recording = RecordingHTTPClient(icingaClient())
        let snap = try await ProviderProbe.probe(pageURL: page, client: recording)
        XCTAssertEqual(snap.provider, .icinga)
        XCTAssertEqual(snap.name, "icinga.example")
        XCTAssertEqual(snap.url, URL(string: "https://icinga.example:5665/v1"))
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components.first?.name, "Web 1")
        XCTAssertEqual(Set(recording.requested.map(\.path)), ["/v1/objects/hosts", "/v1/objects/services"])
        XCTAssertFalse(recording.requested.contains { $0.path.contains("summary.json") })
    }

    func testPort5665WithV1IsIcingaWithoutIcingaInHost() async throws {
        let url = URL(string: "https://monitor.example:5665/v1")!
        var inner = MapHTTPClient()
        inner.byPath["/v1/objects/hosts"] = (Data("{\"results\":[]}".utf8), 200)
        inner.byPath["/v1/objects/services"] = (Data("{\"results\":[]}".utf8), 200)
        let snap = try await ProviderProbe.probe(pageURL: url, client: inner)
        XCTAssertEqual(snap.provider, .icinga)
        XCTAssertEqual(snap.name, "monitor.example")
    }

    func testNonIcingaURLDoesNotFetchIcingaObjects() async {
        var inner = MapHTTPClient()
        inner.byPath["/v1/objects/hosts"] = (hostsJSON, 200)
        inner.byPath["/v1/objects/services"] = (servicesJSON, 200)
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
        XCTAssertFalse(recording.requested.contains { $0.path.contains("/objects/") })
    }

    func testUnauthorizedOnIcinga401() async {
        var inner = MapHTTPClient()
        inner.byPath["/v1/objects/hosts"] = (Data(), 401)
        inner.byPath["/v1/objects/services"] = (servicesJSON, 200)
        do {
            _ = try await ProviderProbe.probe(pageURL: page, client: inner)
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unauthorized)
        }
    }

    func testUnreachableOnIcinga500() async {
        var inner = MapHTTPClient()
        inner.byPath["/v1/objects/hosts"] = (Data(), 500)
        inner.byPath["/v1/objects/services"] = (servicesJSON, 200)
        do {
            _ = try await ProviderProbe.probe(pageURL: page, client: inner)
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    func testPreferIcingaSkipsOtherProviders() async throws {
        var inner = icingaClient()
        inner.byPath["/api/v2/summary.json"] = (Data("{}".utf8), 200)
        inner.byPath["/summary.json"] = (Data("{}".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(pageURL: page, client: recording, prefer: .icinga)
        XCTAssertEqual(snap.provider, .icinga)
        XCTAssertEqual(Set(recording.requested.map(\.path)), ["/v1/objects/hosts", "/v1/objects/services"])
    }

    func testUnchangedBodiesSkipParse() async throws {
        let client = icingaClient()
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .icinga)
        ProviderProbe.resetCounts()
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .icinga,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(second.snapshot, first.snapshot)
        XCTAssertEqual(ProviderProbe.parseCount, 0)
    }

    func testMonitorAddKeepsUserinfoAndStripsSnapshotURL() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = Monitor(store: PageStore(directory: dir), client: icingaClient())
        try await monitor.add(url: page, name: nil)
        XCTAssertEqual(monitor.pages[0].url.user, "tg_alert_monitor")
        XCTAssertEqual(monitor.pages[0].url.password, "s3cret")
        XCTAssertEqual(monitor.pages[0].name, "icinga.example")
        XCTAssertNil(monitor.pages[0].snapshot?.url.user)
        XCTAssertEqual(monitor.pages[0].snapshot?.url, URL(string: "https://icinga.example:5665/v1"))
    }

    func testUnauthorizedErrorDescribesBasicAuth() {
        XCTAssertEqual(
            ProbeError.unauthorized.errorDescription,
            "That URL requires a username and password in the URL (https://user:password@host/...)."
        )
    }

    private func icingaClient() -> MapHTTPClient {
        var client = MapHTTPClient()
        client.byPath["/v1/objects/hosts"] = (hostsJSON, 200)
        client.byPath["/v1/objects/services"] = (servicesJSON, 200)
        return client
    }
}
