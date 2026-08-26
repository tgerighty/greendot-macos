import AppKit
import XCTest
@testable import greendot
@testable import StatusCore
import TestSupport

/// Repeatable in-memory timings for the shipped parse, poll, menu, and icon paths.
/// Prints `BENCH name=ms` lines. Does not gate on absolute microseconds.
@MainActor
final class PerformanceHarnessTests: XCTestCase {
    private static let delayMs = 80.0
    private static let noopHandlers = StatusMenuHandlers(
        onAdd: {},
        onEdit: { _ in },
        onRemove: { _ in },
        onToggleNotifications: { _ in },
        onOpen: { _ in },
        onRefresh: {},
        onToggleLaunchAtLogin: {},
        onAbout: {},
        onQuit: {}
    )

    func testEmitBenchTimings() async throws {
        guard ProcessInfo.processInfo.environment["GREENDOT_BENCH"] == "1" else {
            throw XCTSkip("Run this harness with make bench")
        }
        _ = NSApplication.shared

        let parse = measureParse()
        let poll = try await measurePoll()
        let menu = measureMenu()
        let icon = measureStatusDot()
        let save = measureStoreSave()
        let unchangedWrites = try await measureUnchangedPollWrites()
        let remaining = try await measureRemaining()

        let lines = [
            "BENCH parse_statuspage_ms=\(fmt(parse.statuspage))",
            "BENCH parse_instatus_ms=\(fmt(parse.instatus))",
            "BENCH parse_statuspal_ms=\(fmt(parse.statuspal))",
            "BENCH pollAll_3page_delay_ms=\(fmt(poll.elapsedMs))",
            "BENCH pollAll_3page_delay_expected_sequential_ms=\(fmt(3 * Self.delayMs))",
            "BENCH pollAll_3page_get_count=\(poll.getCount)",
            "BENCH pollAll_mixed_get_count=\(poll.mixedGetCount)",
            "BENCH menu_build_ms=\(fmt(menu.uncachedBuildMs))",
            "BENCH menu_build_cached_ms=\(fmt(menu.cachedBuildMs))",
            "BENCH status_dot_ms=\(fmt(icon.elapsedMs))",
            "BENCH status_dot_unique_images=\(icon.uniqueCount)",
            "BENCH store_save_ms=\(fmt(save))",
            "BENCH pollAll_unchanged_config_rewrites=\(unchangedWrites)",
            "BENCH statuspal_first_probe_gets=\(remaining.statuspalGets)",
            "BENCH menu_unique_objects=\(menu.uniqueCount)",
            "BENCH statuspal_regex_compiles=\(remaining.regexCompiles)",
            "BENCH poll_second_parse_count=\(remaining.secondParseCount)",
            "BENCH pulse_refresh_when_reachable=\(remaining.pulseWhenReachable)"
        ]
        for line in lines {
            print(line)
        }
        XCTAssertGreaterThan(parse.statuspage, 0)
        XCTAssertGreaterThan(poll.elapsedMs, 0)
        XCTAssertGreaterThan(menu.uncachedBuildMs, 0)
        XCTAssertGreaterThan(menu.cachedBuildMs, 0)
        XCTAssertEqual(menu.uniqueCount, 1, "Repeated cached builds must reuse one menu")
        XCTAssertGreaterThan(icon.elapsedMs, 0)
        XCTAssertGreaterThan(poll.getCount, 0)
        XCTAssertGreaterThan(remaining.statuspalGets, 0)
    }
}

private extension PerformanceHarnessTests {
    func measureParse() -> ParseMetrics {
        let statuspage = Self.statuspageJSON(name: "GitHub", components: 40)
        let instatus = Data("""
        {"page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"},
         "components": [{"name": "API", "status": "OPERATIONAL"}],
         "activeIncidents": []}
        """.utf8)
        let statuspal = Data("""
        {
          "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
          "current_status_type": null,
          "services": [
            {"name": "IaaS", "current_incident_type": null, "children": [
              {"name": "Object Storage", "current_incident_type": null, "children": []},
              {"name": "Compute", "current_incident_type": null, "children": []}
            ]}
          ],
          "incidents": []
        }
        """.utf8)
        let statuspageURL = URL(string: "https://www.githubstatus.com")!
        let instatusURL = URL(string: "https://instat.us")!
        let statuspalURL = URL(string: "https://acme.statuspal.io")!
        return ParseMetrics(
            statuspage: elapsedMs(iterations: 400) {
                _ = try StatuspageParser.parse(data: statuspage, sourceURL: statuspageURL)
            },
            instatus: elapsedMs(iterations: 400) {
                _ = try InstatusParser.parse(data: instatus, sourceURL: instatusURL)
            },
            statuspal: elapsedMs(iterations: 400) {
                _ = try StatuspalParser.parse(data: statuspal, sourceURL: statuspalURL)
            }
        )
    }

    func measurePoll() async throws -> PollMetrics {
        let json = Self.statuspageJSON(name: "GitHub", components: 8)
        let sequential = MapHTTPClient(byPath: ["/api/v2/summary.json": (json, 200)])
        let delayClient = DelayHTTPClient(inner: sequential, nanoseconds: BenchmarkFixtures.delayNanoseconds)
        let counting = RecordingHTTPClient(delayClient)
        let threePage = try await pollPages(
            client: counting,
            pages: [
                BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage),
                BenchmarkFixtures.greenPage(host: "b.example", name: "B", provider: .statuspage),
                BenchmarkFixtures.greenPage(host: "c.example", name: "C", provider: .statuspage)
            ]
        )

        var mixedMap = MapHTTPClient()
        mixedMap.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (json, 200)
        mixedMap.byURL["https://instat.us/summary.json"] = (Data("""
        {"page": {"name": "Instatus", "url": "https://instat.us", "status": "UP"}}
        """.utf8), 200)
        mixedMap.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Data("""
        {
          "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
          "current_status_type": null,
          "services": [],
          "incidents": []
        }
        """.utf8), 200)
        let mixedCounting = RecordingHTTPClient(mixedMap)
        _ = try await pollPages(
            client: mixedCounting,
            pages: [
                BenchmarkFixtures.greenPage(host: "www.githubstatus.com", name: "GitHub", provider: .statuspage),
                BenchmarkFixtures.greenPage(host: "instat.us", name: "Instatus", provider: .instatus),
                BenchmarkFixtures.greenPage(host: "acme.statuspal.io", name: "Acme", provider: .statuspal)
            ]
        )
        return PollMetrics(
            elapsedMs: threePage.elapsedMs,
            getCount: counting.requested.count,
            mixedGetCount: mixedCounting.requested.count
        )
    }

    func pollPages(
        client: HTTPClient,
        pages: [WatchedPage]
    ) async throws -> PollPageMetrics {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = pages
        try store.save(config)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let start = ContinuousClock.now
        let toasts = try await monitor.pollAll()
        let elapsed = start.duration(to: .now)
        return PollPageMetrics(
            elapsedMs: elapsed.milliseconds,
            toasts: toasts,
            snapshots: monitor.pages.map(\.snapshot)
        )
    }

    struct MenuMetrics {
        var uncachedBuildMs: Double
        var cachedBuildMs: Double
        var uniqueCount: Int
    }

    func measureMenu() -> MenuMetrics {
        let pages = (0..<6).map { index in
            Self.nestedPage(name: "Page \(index)", host: "status\(index).example")
        }
        let state = StatusMenuState(pages: pages, severity: .green, launchAtLoginEnabled: false)
        let uncachedBuildMs = elapsedMs(iterations: 80) {
            let builder = MenuBuilder(handlers: Self.noopHandlers)
            _ = builder.build(for: state)
        }
        let cachedBuilder = MenuBuilder(handlers: Self.noopHandlers)
        var cachedMenus: [NSMenu] = []
        cachedMenus.reserveCapacity(80)
        let cachedBuildMs = elapsedMs(iterations: 80) {
            cachedMenus.append(cachedBuilder.build(for: state))
        }
        return MenuMetrics(
            uncachedBuildMs: uncachedBuildMs,
            cachedBuildMs: cachedBuildMs,
            uniqueCount: Set(cachedMenus.map(ObjectIdentifier.init)).count
        )
    }

    struct RemainingMetrics {
        var statuspalGets: Int
        var regexCompiles: Int
        var secondParseCount: Int
        var pulseWhenReachable: Int
    }

    func measureRemaining() async throws -> RemainingMetrics {
        RemainingMetrics(
            statuspalGets: try await measureStatuspalProbe(),
            regexCompiles: measureRegexCompilation(),
            secondParseCount: try await measureSecondPollParseCount(),
            pulseWhenReachable: measureReachablePulseRefresh()
        )
    }

    func measureStatuspalProbe() async throws -> Int {
        var statuspalMap = MapHTTPClient()
        statuspalMap.byURL["https://statuspal.io/api/v2/status_pages/acme/summary"] = (Data("""
        {
          "status_page": {"name": "Acme", "url": "https://acme.statuspal.io"},
          "current_status_type": null,
          "services": [],
          "incidents": []
        }
        """.utf8), 200)
        let statuspalRecording = RecordingHTTPClient(statuspalMap)
        _ = try await ProviderProbe.probe(
            pageURL: URL(string: "https://acme.statuspal.io")!,
            client: statuspalRecording
        )
        return statuspalRecording.requested.count
    }

    func measureRegexCompilation() -> Int {
        ProviderProbe.resetCounts()
        let html = String(repeating: "statuspal.io/api/v2/status_pages/acme plus filler ", count: 40)
        for _ in 0..<500 {
            _ = ProviderProbe.extractStatuspalSubdomain(from: html)
        }
        return ProviderProbe.regexCompileCount
    }

    func measureSecondPollParseCount() async throws -> Int {
        let json = Self.statuspageJSON(name: "GitHub", components: 8)
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (json, 200)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage),
            BenchmarkFixtures.greenPage(host: "b.example", name: "B", provider: .statuspage),
            BenchmarkFixtures.greenPage(host: "c.example", name: "C", provider: .statuspage)
        ]
        try store.save(config)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        _ = try await monitor.pollAll()
        ProviderProbe.resetCounts()
        _ = try await monitor.pollAll()
        return ProviderProbe.parseCount
    }
}

private extension PerformanceHarnessTests {
    func measureReachablePulseRefresh() -> Int {
        var pulse = 0
        for _ in 0..<240 where AppDelegate.shouldRefreshIconOnPulse(hasUnreachable: false) {
            pulse += 1
        }
        return pulse
    }

    func measureStatusDot() -> (elapsedMs: Double, uniqueCount: Int) {
        var images: [NSImage] = []
        images.reserveCapacity(2_000)
        let durationMs = elapsedMs(iterations: 1) {
            for _ in 0..<500 {
                for severity in [Severity.green, .yellow, .red, .grey] {
                    images.append(StatusDot.image(severity, size: 14))
                }
            }
        }
        let unique = Set(images.map(ObjectIdentifier.init)).count
        return (durationMs, unique)
    }

    func measureStoreSave() -> Double {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = (0..<6).map {
            BenchmarkFixtures.greenPage(host: "p\($0).example", name: "P\($0)", provider: .statuspage)
        }
        return elapsedMs(iterations: 40) {
            try store.save(config)
        }
    }

    /// Second poll of identical JSON: 1 if config.json was replaced, 0 if not.
    func measureUnchangedPollWrites() async throws -> Int {
        let json = Self.statuspageJSON(name: "GitHub", components: 8)
        let client = MapHTTPClient(byPath: ["/api/v2/summary.json": (json, 200)])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage)]
        try store.save(config)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        _ = try await monitor.pollAll()
        let path = store.configURL.path
        let before = try FileManager.default.attributesOfItem(atPath: path)
        let beforeInode = before[.systemFileNumber] as? NSNumber
        _ = try await monitor.pollAll()
        let after = try FileManager.default.attributesOfItem(atPath: path)
        let afterInode = after[.systemFileNumber] as? NSNumber
        return beforeInode == afterInode ? 0 : 1
    }

    func elapsedMs(iterations: Int, _ body: () throws -> Void) -> Double {
        do {
            let start = ContinuousClock.now
            for _ in 0..<iterations {
                try body()
            }
            return start.duration(to: .now).milliseconds
        } catch {
            XCTFail("harness body failed: \(error)")
            return -1
        }
    }

    func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    static func statuspageJSON(name: String, components: Int) -> Data {
        var rows: [String] = [
            #"{"id":"g1","name":"Web","status":"operational","group":true}"#
        ]
        for index in 0..<components {
            rows.append(
                #"{"id":"c\#(index)","name":"Component \#(index)","status":"operational","group":false,"#
                    + #""group_id":"g1"}"#
            )
        }
        let joined = rows.joined(separator: ",")
        return Data("""
        {
          "page": {"name": "\(name)", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [\(joined)],
          "incidents": []
        }
        """.utf8)
    }

    static func nestedPage(name: String, host: String) -> WatchedPage {
        let url = URL(string: "https://\(host)")!
        let group = ComponentStatus(
            name: "Web Application",
            severity: .green,
            statusText: "Operational",
            id: "g1",
            children: [
                ComponentStatus(name: "Login/SSO", severity: .green, statusText: "Operational", id: "c1"),
                ComponentStatus(name: "Search", severity: .yellow, statusText: "Degraded", id: "c2"),
                ComponentStatus(name: "API", severity: .green, statusText: "Operational", id: "c3")
            ],
            isGroup: true
        )
        return WatchedPage(
            url: url,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: .yellow,
                components: [group],
                incidents: [Incident(title: "Search slow", url: url)],
                isUnreachable: false
            )
        )
    }
}
