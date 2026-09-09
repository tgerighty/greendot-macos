import XCTest
@testable import StatusCore
import TestSupport

final class NetworkReachabilityTests: XCTestCase {
    private let greenJSON = Data("""
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """.utf8)

    func testPathReachabilityStartsOnlineAndStopIsSafe() {
        let reachability = PathNetworkReachability()
        XCTAssertTrue(reachability.isOnline)
        reachability.start()
        reachability.start()
        reachability.stop()
    }

    func testIsSystemOnlineFollowsReachabilityAndDefaultsToTrue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        let client = FailIfCalledHTTPClient()

        XCTAssertTrue(Monitor(store: store, client: client).isSystemOnline)

        let reachability = FakeNetworkReachability()
        let monitor = Monitor(store: store, client: client, reachability: reachability)
        XCTAssertTrue(monitor.isSystemOnline)
        reachability.isOnline = false
        XCTAssertFalse(monitor.isSystemOnline)
    }

    func testOfflinePollMakesNoHTTPRequest() async throws {
        let seed = try seededMonitor(
            client: FailIfCalledHTTPClient(),
            reachability: FakeNetworkReachability(isOnline: false),
            hosts: ["a.example", "b.example"]
        )
        defer { try? FileManager.default.removeItem(at: seed.directory) }

        let toasts = try await seed.monitor.pollAll()
        XCTAssertEqual(toasts, [NetworkToast.lost])
        XCTAssertTrue(seed.monitor.showingNetworkLoss)
        XCTAssertTrue(seed.monitor.pages.allSatisfy { $0.snapshot?.isUnreachable == true })
    }

    func testOfflinePollEmitsOneLostToastThenNothing() async throws {
        let seed = try seededMonitor(
            client: FailIfCalledHTTPClient(),
            reachability: FakeNetworkReachability(isOnline: false),
            hosts: ["a.example", "b.example"]
        )
        defer { try? FileManager.default.removeItem(at: seed.directory) }

        let lost = try await seed.monitor.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])
        let stillLost = try await seed.monitor.pollAll()
        XCTAssertEqual(stillLost, [])
        XCTAssertTrue(seed.monitor.showingNetworkLoss)
    }

    func testReturningOnlineEmitsTheRegainedToast() async throws {
        let reachability = FakeNetworkReachability(isOnline: false)
        let client = RecordingHTTPClient(MapHTTPClient(byPath: ["/api/v2/summary.json": (greenJSON, 200)]))
        let seed = try seededMonitor(client: client, reachability: reachability, hosts: ["a.example", "b.example"])
        defer { try? FileManager.default.removeItem(at: seed.directory) }

        let lost = try await seed.monitor.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])
        XCTAssertEqual(client.requested, [])

        reachability.isOnline = true
        let regained = try await seed.monitor.pollAll()
        XCTAssertEqual(regained, [NetworkToast.regained])
        XCTAssertFalse(client.requested.isEmpty)
        XCTAssertFalse(seed.monitor.showingNetworkLoss)
    }

    func testSingleWatchedPageStillGetsTheLostToastWhenTheSystemIsOffline() async throws {
        let seed = try seededMonitor(
            client: FailIfCalledHTTPClient(),
            reachability: FakeNetworkReachability(isOnline: false),
            hosts: ["a.example"]
        )
        defer { try? FileManager.default.removeItem(at: seed.directory) }

        let lost = try await seed.monitor.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])
        XCTAssertTrue(seed.monitor.showingNetworkLoss)
        XCTAssertEqual(seed.monitor.pages.count, 1)
    }

    private struct Seed {
        let monitor: Monitor
        let directory: URL
    }

    private func seededMonitor(
        client: HTTPClient,
        reachability: FakeNetworkReachability,
        hosts: [String]
    ) throws -> Seed {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        var config = AppConfig()
        config.pages = hosts.map { host in
            BenchmarkFixtures.greenPage(host: host, name: String(host.prefix(1)).uppercased(), provider: .statuspage)
        }
        try store.save(config)
        let monitor = Monitor(store: store, client: client, reachability: reachability)
        try monitor.load()
        return Seed(monitor: monitor, directory: directory)
    }
}

private struct FailIfCalledHTTPClient: HTTPClient {
    func get(_ url: URL) async throws -> (Data, Int) {
        XCTFail("HTTP was called while the system is offline")
        throw URLError(.notConnectedToInternet)
    }
}
