import XCTest
@testable import StatusCore
import TestSupport

final class PollPerformanceTests: XCTestCase {
    private static let delayNs: UInt64 = 80_000_000
    private static let statuspageJSON = Data("""
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "minor"},
      "components": [{"name": "API", "status": "degraded_performance", "group": false}],
      "incidents": [{"name": "API slow"}]
    }
    """.utf8)
    private static let instatusJSON = Data("""
    {
      "page": {"name": "Instatus", "url": "https://instat.us", "status": "HASISSUES"},
      "components": [{"name": "API", "status": "MAJOROUTAGE"}],
      "activeIncidents": [{"name": "API", "impact": "MAJOROUTAGE"}]
    }
    """.utf8)
    private static let statuspalJSON = Data("""
    {
      "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
      "current_status_type": null,
      "services": [{"name": "API", "current_incident_type": null, "children": []}],
      "incidents": []
    }
    """.utf8)

    func testPollAllOverlapsIndependentPageProbes() async throws {
        let inner = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let delayed = DelayHTTPClient(inner: inner, nanoseconds: Self.delayNs)
        let probe = ConcurrencyProbeHTTPClient(delayed)
        let (monitor, dir) = try seededMonitor(
            client: probe,
            pages: [
                Self.page(host: "a.example", name: "A", provider: .statuspage),
                Self.page(host: "b.example", name: "B", provider: .statuspage),
                Self.page(host: "c.example", name: "C", provider: .statuspage)
            ]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let toasts = try await monitor.pollAll()

        XCTAssertEqual(monitor.pages.map { $0.snapshot?.provider }, [.statuspage, .statuspage, .statuspage])
        XCTAssertEqual(monitor.pages.map(\.displaySeverity), [.yellow, .yellow, .yellow])
        XCTAssertEqual(toasts.map(\.body), ["Degraded", "Degraded", "Degraded"])
        XCTAssertEqual(monitor.barSeverity(), .yellow)
        XCTAssertGreaterThanOrEqual(probe.peakInFlight, 3)
    }

    func testKnownProviderRepollDoesNotIssueOtherProviderGets() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Self.statuspageJSON, 200)
        inner.byURL["https://instat.us/summary.json"] = (Self.instatusJSON, 200)
        inner.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Self.statuspalJSON, 200)
        let recording = RecordingHTTPClient(inner)
        let (monitor, dir) = try seededMonitor(
            client: recording,
            pages: [
                Self.page(host: "www.githubstatus.com", name: "GitHub", provider: .statuspage),
                Self.page(host: "instat.us", name: "Instatus", provider: .instatus),
                Self.page(host: "acme.statuspal.io", name: "Acme", provider: .statuspal)
            ]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let toasts = try await monitor.pollAll()
        let urls = recording.requested.map(\.absoluteString)

        XCTAssertEqual(monitor.pages.map { $0.snapshot?.provider }, [.statuspage, .instatus, .statuspal])
        XCTAssertEqual(monitor.pages.map(\.displaySeverity), [.yellow, .red, .green])
        XCTAssertEqual(monitor.pages.map { $0.snapshot?.incidents.first?.title }, ["API slow", "API", nil])
        XCTAssertEqual(toasts.map(\.pageName), ["GitHub", "Instatus"])
        XCTAssertEqual(toasts.map(\.body), ["Degraded", "Major outage"])
        XCTAssertEqual(monitor.barSeverity(), .red)

        XCTAssertEqual(urls.filter { $0.contains("www.githubstatus.com") }, [
            "https://www.githubstatus.com/api/v2/summary.json"
        ])
        XCTAssertEqual(urls.filter { $0.contains("instat.us") }, [
            "https://instat.us/summary.json"
        ])
        XCTAssertFalse(urls.contains { $0.contains("acme.statuspal.io") }, urls.joined(separator: " "))
        XCTAssertEqual(urls.filter { $0.contains("statuspal.io/api") }, [
            "https://statuspal.io/api/v2/status_pages/acme/summary"
        ])
        XCTAssertEqual(recording.requested.count, 3)
    }

    func testFirstStatuspalProbeOnNamedHostDoesNotGetHTML() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Self.statuspalJSON, 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://acme.statuspal.io")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .statuspal)
        XCTAssertEqual(snap.name, "Acme")
        XCTAssertEqual(snap.overall, .green)
        let urls = recording.requested.map(\.absoluteString)
        XCTAssertFalse(urls.contains("https://acme.statuspal.io"), urls.joined(separator: " "))
        XCTAssertTrue(urls.contains("https://statuspal.io/api/v2/status_pages/acme/summary"))
        XCTAssertEqual(recording.requested.count, 3)
    }

    func testUnchangedBodySkipsParseOnSecondPoll() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let (monitor, dir) = try seededMonitor(
            client: client,
            pages: [Self.page(host: "a.example", name: "A", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        ProviderProbe.resetCounts()
        let first = try await monitor.pollAll()
        XCTAssertEqual(ProviderProbe.parseCount, 1)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
        XCTAssertEqual(first.map(\.body), ["Degraded"])
        ProviderProbe.resetCounts()
        let second = try await monitor.pollAll()
        XCTAssertEqual(ProviderProbe.parseCount, 0)
        XCTAssertEqual(second, [])
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
        XCTAssertEqual(monitor.pages[0].snapshot?.incidents.first?.title, "API slow")
    }

    func testStatuspalRegexCompilesOnce() {
        let html = "prefix statuspal.io/api/v2/status_pages/acme/summary suffix"
        XCTAssertEqual(ProviderProbe.extractStatuspalSubdomain(from: html), "acme")
        let afterFirst = ProviderProbe.regexCompileCount
        XCTAssertEqual(ProviderProbe.extractStatuspalSubdomain(from: html), "acme")
        XCTAssertEqual(ProviderProbe.extractStatuspalSubdomain(from: html), "acme")
        XCTAssertEqual(ProviderProbe.regexCompileCount, afterFirst)
    }

    func testPreferredProviderMissFallsBackToOthers() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: client,
            prefer: .instatus
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertEqual(snap.name, "GitHub")
        XCTAssertEqual(snap.overall, .yellow)
    }

    func testUnchangedPollDoesNotRewriteConfig() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let (monitor, dir) = try seededMonitor(
            client: client,
            pages: [Self.page(host: "a.example", name: "A", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let configURL = PageStore(directory: dir).configURL
        _ = try await monitor.pollAll()
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
        XCTAssertEqual(monitor.pages[0].snapshot?.incidents.first?.title, "API slow")
        let afterFirst = try inode(configURL)
        _ = try await monitor.pollAll()
        let afterSecond = try inode(configURL)
        XCTAssertEqual(afterFirst, afterSecond)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
    }

    func testChangedPollStillRewritesConfig() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Self.statuspageJSON, 200)
        ])
        let (monitor, dir) = try seededMonitor(
            client: client,
            pages: [Self.page(host: "a.example", name: "A", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let configURL = PageStore(directory: dir).configURL
        let before = try inode(configURL)
        _ = try await monitor.pollAll()
        let after = try inode(configURL)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .yellow)
    }

    func testPollAllUnreachablePageStaysGreyAndToasts() async throws {
        let (monitor, dir) = try seededMonitor(
            client: MapHTTPClient(),
            pages: [Self.page(host: "offline.example", name: "Down", provider: .statuspage)]
        )
        defer { try? FileManager.default.removeItem(at: dir) }
        let toasts = try await monitor.pollAll()
        XCTAssertEqual(monitor.pages[0].snapshot?.isUnreachable, true)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .grey)
        XCTAssertEqual(monitor.barSeverity(), .grey)
        XCTAssertEqual(toasts.map(\.body), ["Unreachable"])
    }

    private func inode(_ url: URL) throws -> NSNumber {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let value = attrs[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(value)
        return value ?? 0
    }

    private func seededMonitor(
        client: HTTPClient,
        pages: [WatchedPage]
    ) throws -> (Monitor, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = pages
        try store.save(config)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        return (monitor, dir)
    }

    private static func page(host: String, name: String, provider: StatusProvider) -> WatchedPage {
        let url = URL(string: "https://\(host)")!
        return WatchedPage(
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: provider,
                overall: .green,
                components: [ComponentStatus(name: "API", severity: .green, statusText: "Operational")],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}

final class ConcurrencyProbeHTTPClient: HTTPClient, @unchecked Sendable {
    private let inner: any HTTPClient
    private let lock = NSLock()
    private var inFlight = 0
    private var peak = 0

    init(_ inner: any HTTPClient) {
        self.inner = inner
    }

    var peakInFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        begin()
        defer { end() }
        return try await inner.get(url)
    }

    private func begin() {
        lock.lock()
        inFlight += 1
        peak = max(peak, inFlight)
        lock.unlock()
    }

    private func end() {
        lock.lock()
        inFlight -= 1
        lock.unlock()
    }
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
