import XCTest
@testable import StatusCore
import TestSupport

final class NetworkToastTests: XCTestCase {
    private let greenJSON = Data("""
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """.utf8)

    func testAllPagesUnreachableCollapsesToOneLostToast() {
        let current = [page("A", .grey), page("B", .grey)]
        let pageToasts = [toast(current[0], .grey), toast(current[1], .grey)]
        var showingLost = false

        XCTAssertEqual(NetworkToast.apply(pageToasts, pages: current, showingLost: &showingLost), [NetworkToast.lost])
        XCTAssertTrue(showingLost)
    }

    func testRecoveryReplacesGreenToastsAndKeepsOthers() {
        let current = [page("A", .green), page("B", .red)]
        let pageToasts = [toast(current[0], .green), toast(current[1], .red)]
        var showingLost = true

        XCTAssertEqual(
            NetworkToast.apply(pageToasts, pages: current, showingLost: &showingLost),
            [NetworkToast.regained, pageToasts[1]]
        )
        XCTAssertFalse(showingLost)
    }

    func testPartialRecoveryStillReportsAPageThatIsDown() {
        let current = [page("A", .green), page("B", .grey)]
        var showingLost = true

        XCTAssertEqual(
            NetworkToast.apply([toast(current[0], .green)], pages: current, showingLost: &showingLost),
            [NetworkToast.regained, toast(current[1], .grey)]
        )
        XCTAssertFalse(showingLost)
    }

    func testRemovingAPageStillLetsTheLostToastClearOnRecovery() {
        let current = [page("A", .green)]
        var showingLost = true

        XCTAssertEqual(
            NetworkToast.apply([toast(current[0], .green)], pages: current, showingLost: &showingLost),
            [NetworkToast.regained]
        )
        XCTAssertFalse(showingLost)
    }

    /// One page cannot claim a network outage, so the claim is withdrawn. Nothing answered, so it
    /// must be withdrawn quietly rather than by announcing a recovery that did not happen.
    func testTooFewPagesWithdrawsTheClaimWithoutClaimingRecovery() {
        let current = [page("A", .grey)]
        var showingLost = true

        XCTAssertEqual(
            NetworkToast.apply([], pages: current, showingLost: &showingLost),
            [toast(current[0], .grey)]
        )
        XCTAssertFalse(showingLost)
    }

    func testRemovingEveryPageWithdrawsTheClaimWithoutClaimingRecovery() {
        var showingLost = true

        XCTAssertEqual(NetworkToast.apply([], pages: [], showingLost: &showingLost), [])
        XCTAssertFalse(showingLost)
    }

    /// A page that has never been polled has unknown reachability, which is not a recovery.
    func testAPageWithNoResultYetDoesNotClaimRecovery() {
        let unpolled = WatchedPage(url: URL(string: "https://c.example")!, name: "C")
        var showingLost = true

        XCTAssertEqual(
            NetworkToast.apply([], pages: [page("A", .grey), unpolled], showingLost: &showingLost),
            [toast(page("A", .grey), .grey), Toast(
                pageID: unpolled.id,
                pageName: "C",
                body: "Unreachable",
                severity: .grey
            )]
        )
        XCTAssertFalse(showingLost)
    }

    func testRecoveryClearsTheLostToastEvenWhenEveryPageIsMuted() {
        let current = [page("A", .green, muted: true), page("B", .green, muted: true)]
        var showingLost = true

        XCTAssertEqual(NetworkToast.apply([], pages: current, showingLost: &showingLost), [NetworkToast.regained])
        XCTAssertFalse(showingLost)
    }

    func testSingleUnreachablePageKeepsItsOwnToast() {
        let current = [page("A", .grey)]
        let pageToasts = [toast(current[0], .grey)]
        var showingLost = false

        XCTAssertEqual(NetworkToast.apply(pageToasts, pages: current, showingLost: &showingLost), pageToasts)
        XCTAssertFalse(showingLost)
    }

    func testPartialOutageKeepsPageToasts() {
        let current = [page("A", .grey), page("B", .green)]
        let pageToasts = [toast(current[0], .grey)]
        var showingLost = false

        XCTAssertEqual(NetworkToast.apply(pageToasts, pages: current, showingLost: &showingLost), pageToasts)
        XCTAssertFalse(showingLost)
    }

    func testStayingOfflineEmitsNothing() {
        let current = [page("A", .grey), page("B", .grey)]
        var showingLost = true

        XCTAssertEqual(NetworkToast.apply([], pages: current, showingLost: &showingLost), [])
        XCTAssertTrue(showingLost)
    }

    func testAllPagesMutedSuppressesNetworkToast() {
        let current = [page("A", .grey, muted: true), page("B", .grey, muted: true)]
        var showingLost = false

        XCTAssertEqual(NetworkToast.apply([], pages: current, showingLost: &showingLost), [])
        XCTAssertFalse(showingLost)
    }

    func testLostWaitsForClickAndRegainedClearsIt() {
        XCTAssertEqual(NetworkToast.lost.body, "Greendot has no network connectivity")
        XCTAssertEqual(NetworkToast.regained.body, "Greendot has regained network connectivity")
        XCTAssertNil(NetworkToast.lost.autoDismissSeconds)
        XCTAssertNotNil(NetworkToast.regained.autoDismissSeconds)
        XCTAssertEqual(NetworkToast.lost.pageID, NetworkToast.regained.pageID)
    }

    func testPollAllReportsNetworkLossAndRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            BenchmarkFixtures.greenPage(host: "a.example", name: "A", provider: .statuspage),
            BenchmarkFixtures.greenPage(host: "b.example", name: "B", provider: .statuspage)
        ]
        try store.save(config)

        let client = SwitchableHTTPClient(online: MapHTTPClient(byPath: ["/api/v2/summary.json": (greenJSON, 200)]))
        let monitor = Monitor(store: store, client: client)
        try monitor.load()

        client.isOnline = false
        let lost = try await monitor.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])

        let stillLost = try await monitor.pollAll()
        XCTAssertEqual(stillLost, [])

        client.isOnline = true
        let regained = try await monitor.pollAll()
        XCTAssertEqual(regained, [NetworkToast.regained])
    }

    private func page(_ name: String, _ severity: Severity, muted: Bool = false) -> WatchedPage {
        let url = URL(string: "https://\(name).example")!
        return WatchedPage(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(name == "A" ? 1 : 2)")!,
            url: url,
            name: name,
            notificationsEnabled: !muted,
            snapshot: PageSnapshot(
                name: name,
                url: url,
                provider: .statuspage,
                overall: severity,
                components: [],
                incidents: [],
                isUnreachable: severity == .grey
            )
        )
    }

    private func toast(_ page: WatchedPage, _ severity: Severity) -> Toast {
        Toast(pageID: page.id, pageName: page.name, body: severity.displayName, severity: severity)
    }
}

/// Answers normally while online and fails every request while offline.
final class SwitchableHTTPClient: HTTPClient, @unchecked Sendable {
    private let online: any HTTPClient
    private let lock = NSLock()
    private var storedIsOnline = true

    init(online: any HTTPClient) {
        self.online = online
    }

    var isOnline: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedIsOnline
        }
        set {
            lock.lock()
            storedIsOnline = newValue
            lock.unlock()
        }
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        guard isOnline else { throw URLError(.notConnectedToInternet) }
        return try await online.get(url)
    }
}
