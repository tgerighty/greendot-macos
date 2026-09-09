import XCTest
@testable import StatusCore
import TestSupport

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

    func testMapHTTPClientUsesMutatedByURLProperty() async throws {
        var client = MapHTTPClient()
        let url = URL(string: "https://statuspal.io/api/v2/status_pages/acme/summary")!
        client.byURL[url.absoluteString] = (Data("ok".utf8), 200)
        let result = try await client.get(url)
        XCTAssertEqual(result.1, 200)
        XCTAssertEqual(result.0, Data("ok".utf8))
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

    func testDirectoryClientRejectsPathEscape() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let secretName = "secret-\(UUID().uuidString).txt"
        let secret = dir.deletingLastPathComponent().appendingPathComponent(secretName)
        try Data("secret".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let client = DirectoryHTTPClient(root: dir)
        let escaped = URL(string: "https://www.githubstatus.com/../../\(secretName)")!
        let result = try await client.get(escaped)
        XCTAssertEqual(result.1, 404)
        XCTAssertTrue(result.0.isEmpty)
    }

    func testPathSafetyRejectsParentAndAcceptsChild() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let child = root.appendingPathComponent("www.example.com/api/v2/summary.json")
        let parent = root.deletingLastPathComponent().appendingPathComponent("outside.txt")
        XCTAssertNotNil(PathSafety.contained(child, under: root))
        XCTAssertNil(PathSafety.contained(parent, under: root))
        XCTAssertNil(PathSafety.contained(root.appendingPathComponent(".."), under: root))
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

    func testProbePropagatesCancellation() async {
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://offline.example")!,
                client: CancellationHTTPClient()
            )
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // Cancellation must not be converted into an unreachable result.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
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
        XCTAssertEqual(monitor.displayedSeverity(at: Date()), .green)

        let down = MapHTTPClient()
        let retry = Monitor(store: PageStore(directory: dir), client: down)
        try retry.load()
        let toasts = try await retry.pollAll()
        XCTAssertEqual(retry.pages[0].snapshot?.overall, .grey)
        XCTAssertEqual(retry.displayedSeverity(at: Date()), .grey)
        XCTAssertEqual(toasts.count, 1)
        XCTAssertEqual(toasts[0].body, "Unreachable")
    }

    func testPageStoreLoadMissingFileReturnsEmptyConfigAndDoesNotWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let config = try store.load()
        XCTAssertTrue(config.pages.isEmpty)
        XCTAssertEqual(config.version, AppConfig.currentVersion)
        XCTAssertFalse(config.didSetLaunchAtLogin)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.configURL.path))
    }

    func testPageStoreLoadCorruptJSONThrows() throws {
        try assertLoadThrows(Data("{".utf8), StoreError.corrupt)
    }

    func testPageStoreLoadUnsupportedVersionThrows() throws {
        try assertLoadThrows(
            Data(#"{"version":3,"pages":[],"didSetLaunchAtLogin":false}"#.utf8),
            StoreError.corrupt
        )
    }

    func testPageStoreLoadAcceptsCurrentVersion() throws {
        let dir = try writeConfig(Data(#"{"version":2,"pollSeconds":60,"pages":[]}"#.utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = try PageStore(directory: dir).load()
        XCTAssertTrue(config.pages.isEmpty)
        XCTAssertEqual(config.version, 2)
    }

    func testMonitorLoadThrowsOnCorruptStoreAndLeavesPagesEmpty() throws {
        let dir = try writeConfig(Data("not-json".utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = Monitor(store: PageStore(directory: dir), client: MapHTTPClient())
        XCTAssertThrowsError(try monitor.load()) { error in
            XCTAssertEqual(error as? StoreError, .corrupt)
        }
        XCTAssertTrue(monitor.pages.isEmpty)
    }

    func testMonitorMutationsThrowWhenStoreCannotSave() async throws {
        try await assertSaveThrows(json: statuspageJSON) { try $0.remove(id: $0.pages[0].id) }
        try await assertSaveThrows(json: statuspageJSON) { try $0.toggleNotifications(id: $0.pages[0].id) }
        try await assertSaveThrows(json: statuspageJSON) { try $0.toggleComponent(id: $0.pages[0].id, name: "API") }
        try await assertSaveThrows(json: statuspageJSON) { try $0.setAllComponents(id: $0.pages[0].id, enabled: false) }
    }

    func testStoreErrorCorruptHasUserFacingText() {
        XCTAssertEqual(StoreError.corrupt.errorDescription, "The saved status list could not be read.")
    }
}

extension ProbeAndMonitorTests {
    func testProbeTreatsHTTP429AsUnreachable() async {
        await assertProbeError(.unreachable, status: 429)
    }

    func testProbeTreatsRepresentative5xxAsUnreachable() async {
        await assertProbeError(.unreachable, status: 503)
    }

    func testProbeTreatsMissingHTTPStatusAsUnreachable() async {
        await assertProbeError(.unreachable, status: 0)
    }

    func testProbeKeepsHTTP404AsUnsupported() async {
        await assertProbeError(.unsupported, status: 404)
    }

    func testProbeTreatsStatuspalDiscoveryServerErrorAsUnreachable() async {
        var client = MapHTTPClient()
        let pageURL = testURL(host: "example.com")
        client.byURL[pageURL.absoluteString] = (Data(), 503)

        do {
            _ = try await ProviderProbe.probe(
                pageURL: pageURL,
                client: client
            )
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    private func assertProbeError(_ expected: ProbeError, status: Int) async {
        let pageURL = testURL(host: "example.com")
        let summaryURL = pageURL
            .appendingPathComponent("api")
            .appendingPathComponent("v2")
            .appendingPathComponent("summary.json")
        var client = MapHTTPClient()
        client.byURL[summaryURL.absoluteString] = (Data(), status)

        do {
            _ = try await ProviderProbe.probe(
                pageURL: pageURL,
                client: client
            )
            XCTFail("expected \(expected)")
        } catch {
            XCTAssertEqual(error as? ProbeError, expected)
        }
    }
}

private func writeConfig(_ data: Data) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: dir.appendingPathComponent("config.json"))
    return dir
}

private func assertLoadThrows(_ data: Data, _ expected: StoreError) throws {
    let dir = try writeConfig(data)
    defer { try? FileManager.default.removeItem(at: dir) }
    XCTAssertThrowsError(try PageStore(directory: dir).load()) { error in
        XCTAssertEqual(error as? StoreError, expected)
    }
}

private func assertSaveThrows(json: String, _ work: (Monitor) throws -> Void) async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (Data(json.utf8), 200)])
    let monitor = Monitor(store: PageStore(directory: dir), client: client)
    try await monitor.add(url: URL(string: "https://www.githubstatus.com")!, name: nil)
    let config = dir.appendingPathComponent("config.json")
    try FileManager.default.removeItem(at: config)
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    let before = monitor.pages
    XCTAssertThrowsError(try work(monitor))
    XCTAssertEqual(monitor.pages, before)
}

private struct FailingHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        throw URLError(.cannotConnectToHost)
    }
}

private struct CancellationHTTPClient: HTTPClient {
    func get(_: URL) async throws -> (Data, Int) {
        throw CancellationError()
    }
}
