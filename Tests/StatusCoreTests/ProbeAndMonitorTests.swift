import XCTest
@testable import StatusCore

final class ProbeAndMonitorTests: XCTestCase {
    private let statuspageJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    func testProbePrefersStatuspageSummary() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
        ])
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "GitHub")
    }

    func testProbeFindsInstatus() async throws {
        let json = """
        {"page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"}}
        """
        let client = MapHTTPClient(byPath: [
            "/summary.json": (Data(json.utf8), 200)
        ])
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://instat.us")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .instatus)
    }

    func testProbeFindsStatuspalFromHost() async throws {
        let json = """
        {
          "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
          "current_status_type": null,
          "services": [],
          "incidents": []
        }
        """
        var client = MapHTTPClient()
        client.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Data(json.utf8), 200)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://acme.statuspal.io")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .statuspal)
        XCTAssertEqual(snap.name, "Acme")
    }

    func testDirectoryClientReadsSummaryPath() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let api = dir.appendingPathComponent("api/v2")
        try FileManager.default.createDirectory(at: api, withIntermediateDirectories: true)
        try Data(statuspageJSON.utf8).write(to: dir.appendingPathComponent("api/v2/summary.json"))
        let client = DirectoryHTTPClient(root: dir)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: client
        )
        XCTAssertEqual(snap.name, "GitHub")
    }

    func testDirectoryClientPrefersHostFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let github = dir.appendingPathComponent("www.githubstatus.com/api/v2")
        let box = dir.appendingPathComponent("status.box.com/api/v2")
        try FileManager.default.createDirectory(at: github, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: box, withIntermediateDirectories: true)
        try Data(statuspageJSON.utf8).write(to: github.appendingPathComponent("summary.json"))
        try Data(statuspageJSON.replacingOccurrences(of: "GitHub", with: "Box").utf8)
            .write(to: box.appendingPathComponent("summary.json"))
        let client = DirectoryHTTPClient(root: dir)
        let githubSnap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: client
        )
        let boxSnap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.box.com")!,
            client: client
        )
        XCTAssertEqual(githubSnap.name, "GitHub")
        XCTAssertEqual(boxSnap.name, "Box")
    }

    func testProbeUnknownFormat() async {
        let client = MapHTTPClient()
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

    func testProbeNetworkFailureIsUnreachable() async {
        let client = FailingHTTPClient()
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://offline.example")!,
                client: client
            )
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    func testStoreRoundTripAddEditRemove() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
        ])
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
        XCTAssertEqual(monitor.pages.count, 1)
        XCTAssertEqual(monitor.pages[0].name, "GitHub")
        XCTAssertTrue(monitor.pages[0].notificationsEnabled)

        let id = monitor.pages[0].id
        try await monitor.edit(id: id, url: URL(string: "https://www.githubstatus.com")!, name: "GH")
        XCTAssertEqual(monitor.pages[0].name, "GH")

        try monitor.toggleNotifications(id: id)
        XCTAssertFalse(monitor.pages[0].notificationsEnabled)

        try monitor.remove(id: id)
        XCTAssertTrue(monitor.pages.isEmpty)

        let loaded = Monitor(store: store, client: client)
        try loaded.load()
        XCTAssertTrue(loaded.pages.isEmpty)
    }

    func testPollFailureIsGreyAndDoesNotDriveGreenBar() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let okClient = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
        ])
        let monitor = Monitor(store: PageStore(directory: dir), client: okClient)
        try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
        XCTAssertEqual(monitor.barSeverity(), .green)

        let down = MapHTTPClient()
        let retry = Monitor(store: PageStore(directory: dir), client: down)
        try retry.load()
        let toasts = await retry.pollAll()
        XCTAssertEqual(retry.pages[0].snapshot?.overall, .grey)
        XCTAssertEqual(retry.barSeverity(), .grey)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts[0].body, "Unreachable")
    }
}

private struct FailingHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        throw URLError(.cannotConnectToHost)
    }
}
