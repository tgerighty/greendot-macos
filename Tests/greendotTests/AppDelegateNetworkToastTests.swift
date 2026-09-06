import Foundation
import XCTest
import StatusCore
import TestSupport
@testable import greendot

@MainActor
final class AppDelegateNetworkToastTests: XCTestCase {
    private let greenJSON = Data("""
    {
      "page": {"name": "Page", "url": "https://a.example"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """.utf8)

    /// A page can go grey a poll before the rest. Its panel must not outlive the network toast
    /// that takes over for it.
    func testLostNetworkToastClearsThePanelOfAPageThatWentGreyEarlier() async throws {
        let seed = try seededMonitor()
        let (monitor, client) = (seed.monitor, seed.client)
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        let ids = monitor.pages.map(\.id)

        client.offlineHosts = ["a.example"]
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(delivery.toasts.map(\.pageID), [ids[0]])

        client.offlineHosts = ["a.example", "b.example"]
        await delegate.pollAndRefresh(monitor)

        XCTAssertEqual(delivery.toasts.last, NetworkToast.lost)
        XCTAssertTrue(delivery.clearedPageIDs.contains(ids[0]), "the earlier grey panel must be cleared")
    }

    /// A recovery poll whose delivery is dropped as stale must not strand the grey panel.
    func testALaterPollClearsANetworkToastThatIsNoLongerTrue() async throws {
        let seed = try seededMonitor()
        let (monitor, client) = (seed.monitor, seed.client)
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)

        client.offlineHosts = ["a.example", "b.example"]
        await delegate.pollAndRefresh(monitor)
        XCTAssertEqual(delivery.toasts.last, NetworkToast.lost)

        // The recovery poll commits in the monitor, but its delivery never reaches the screen.
        client.offlineHosts = []
        _ = try await monitor.pollAll()
        XCTAssertFalse(monitor.showingNetworkLoss)

        await delegate.pollAndRefresh(monitor)

        XCTAssertTrue(
            delivery.clearedPageIDs.contains(NetworkToast.pageID),
            "a poll that is not offline must clear a stale network panel"
        )
    }

    private struct Seed {
        let monitor: Monitor
        let client: HostOutageHTTPClient
        let directory: URL
    }

    private func seededMonitor() throws -> Seed {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        var config = AppConfig()
        config.pages = [
            BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage),
            BenchmarkFixtures.greenPage(host: "b.example", name: "B", provider: .statuspage)
        ]
        try store.save(config)
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        return Seed(monitor: monitor, client: client, directory: directory)
    }
}

/// Fails every request to a host in `offlineHosts` and answers the rest with a green page.
final class HostOutageHTTPClient: HTTPClient, @unchecked Sendable {
    private let greenJSON: Data
    private let lock = NSLock()
    private var storedOfflineHosts: Set<String> = []

    init(greenJSON: Data) {
        self.greenJSON = greenJSON
    }

    var offlineHosts: Set<String> {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOfflineHosts
        }
        set {
            lock.lock()
            storedOfflineHosts = newValue
            lock.unlock()
        }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        guard let host = url.host, !offlineHosts.contains(host) else {
            throw URLError(.notConnectedToInternet)
        }
        guard url.path == "/api/v2/summary.json" else { return (Data(), 404) }
        return (greenJSON, 200)
    }
}
