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

        XCTAssertEqual(apply(pageToasts, pages: current, showingLost: &showingLost), [NetworkToast.lost])
        XCTAssertTrue(showingLost)
    }

    func testRecoveryReplacesGreenToastsAndKeepsOthers() {
        let current = [page("A", .green), page("B", .red)]
        let pageToasts = [toast(current[0], .green), toast(current[1], .red)]
        var showingLost = true

        XCTAssertEqual(
            apply(pageToasts, pages: current, showingLost: &showingLost),
            [NetworkToast.regained, pageToasts[1]]
        )
        XCTAssertFalse(showingLost)
    }

    /// A page still unreachable on the poll that brings the network back is usually only late.
    /// It waits one poll for its own toast, as a page that has just gone unreachable does.
    func testPartialRecoveryDefersThePageThatIsStillUnreachable() {
        let current = [page("A", .green), page("B", .grey)]
        var showingLost = true
        var pending: Set<UUID> = []

        XCTAssertEqual(
            NetworkToast.apply(
                [toast(current[0], .green)], pages: current, showingLost: &showingLost, pending: &pending
            ),
            [NetworkToast.regained]
        )
        XCTAssertFalse(showingLost)
        XCTAssertEqual(pending, [current[1].id])
    }

    func testRemovingAPageStillLetsTheLostToastClearOnRecovery() {
        let current = [page("A", .green)]
        var showingLost = true

        XCTAssertEqual(
            apply([toast(current[0], .green)], pages: current, showingLost: &showingLost),
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
            apply([], pages: current, showingLost: &showingLost),
            [toast(current[0], .grey)]
        )
        XCTAssertFalse(showingLost)
    }

    func testRemovingEveryPageWithdrawsTheClaimWithoutClaimingRecovery() {
        var showingLost = true

        XCTAssertEqual(apply([], pages: [], showingLost: &showingLost), [])
        XCTAssertFalse(showingLost)
    }

    /// A page that has never been polled has unknown reachability, which is not a recovery.
    func testAPageWithNoResultYetDoesNotClaimRecovery() {
        let unpolled = WatchedPage(url: URL(string: "https://c.example")!, name: "C")
        var showingLost = true

        XCTAssertEqual(
            apply([], pages: [page("A", .grey), unpolled], showingLost: &showingLost),
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

        XCTAssertEqual(apply([], pages: current, showingLost: &showingLost), [NetworkToast.regained])
        XCTAssertFalse(showingLost)
    }

    func testSingleUnreachablePageKeepsItsOwnToast() {
        let current = [page("A", .grey)]
        let pageToasts = [toast(current[0], .grey)]
        var showingLost = false

        XCTAssertEqual(apply(pageToasts, pages: current, showingLost: &showingLost), pageToasts)
        XCTAssertFalse(showingLost)
    }

    func testPartialOutageKeepsPageToasts() {
        let current = [page("A", .grey), page("B", .green)]
        let pageToasts = [toast(current[0], .grey)]
        var showingLost = false

        XCTAssertEqual(apply(pageToasts, pages: current, showingLost: &showingLost), pageToasts)
        XCTAssertFalse(showingLost)
    }

    func testStayingOfflineEmitsNothing() {
        let current = [page("A", .grey), page("B", .grey)]
        var showingLost = true

        XCTAssertEqual(apply([], pages: current, showingLost: &showingLost), [])
        XCTAssertTrue(showingLost)
    }

    func testAllPagesMutedSuppressesNetworkToast() {
        let current = [page("A", .grey, muted: true), page("B", .grey, muted: true)]
        var showingLost = false

        XCTAssertEqual(apply([], pages: current, showingLost: &showingLost), [])
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

    /// A network drop reaches the pages over more than one poll when it lands while a poll is in
    /// flight. The pages that fail first must not each get a grey toast that the network toast
    /// of the next poll then stands beside.
    func testADropThatSpansTwoPollsStillCollapsesToOneLostToast() async throws {
        let seed = try seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let (monitor, client) = (seed.monitor, seed.client)

        client.offlineHosts = ["b.example", "c.example"]
        let firstPoll = try await monitor.pollAll()
        XCTAssertEqual(firstPoll, [], "pages that have just gone unreachable wait one poll")

        client.offlineHosts = ["a.example", "b.example", "c.example"]
        let secondPoll = try await monitor.pollAll()
        XCTAssertEqual(secondPoll, [NetworkToast.lost])
    }

    func testARecoveryThatSpansTwoPollsGivesNoPageToasts() async throws {
        let seed = try seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let (monitor, client) = (seed.monitor, seed.client)

        client.offlineHosts = ["a.example", "b.example", "c.example"]
        try await assertPoll(monitor, gives: [NetworkToast.lost])

        client.offlineHosts = ["b.example", "c.example"]
        try await assertPoll(monitor, gives: [NetworkToast.regained])

        client.offlineHosts = []
        try await assertPoll(monitor, gives: [])
    }

    func testAPageThatStaysUnreachableAfterARecoveryGetsItsToastOnTheNextPoll() async throws {
        let seed = try seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let (monitor, client) = (seed.monitor, seed.client)

        client.offlineHosts = ["a.example", "b.example", "c.example"]
        try await assertPoll(monitor, gives: [NetworkToast.lost])

        client.offlineHosts = ["b.example"]
        try await assertPoll(monitor, gives: [NetworkToast.regained])

        let nextPoll = try await monitor.pollAll()
        XCTAssertEqual(nextPoll, [greyToast(for: monitor.pages[1])])
    }

    func testAPageUnreachableForOnePollGetsNoToast() async throws {
        let seed = try seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let (monitor, client) = (seed.monitor, seed.client)

        client.offlineHosts = ["b.example"]
        try await assertPoll(monitor, gives: [])

        client.offlineHosts = []
        try await assertPoll(monitor, gives: [], "no grey toast was shown, so there is no recovery to report")
    }

    func testAPageThatStaysUnreachableGetsItsToastOnTheSecondPollAndAGreenOneWhenItReturns() async throws {
        let seed = try seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let (monitor, client) = (seed.monitor, seed.client)
        let pageB = monitor.pages[1]

        client.offlineHosts = ["b.example"]
        try await assertPoll(monitor, gives: [])
        try await assertPoll(monitor, gives: [greyToast(for: pageB)])

        client.offlineHosts = []
        try await assertPoll(monitor, gives: [toast(pageB, .green)])
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
        config.pages = ["a", "b", "c"].map {
            BenchmarkFixtures.greenPage(host: "\($0).example", name: $0.uppercased(), provider: .statuspage)
        }
        try store.save(config)
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        return Seed(monitor: monitor, client: client, directory: directory)
    }

    private func assertPoll(
        _ monitor: Monitor, gives expected: [Toast], _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let toasts = try await monitor.pollAll()
        XCTAssertEqual(toasts, expected, message, file: file, line: line)
    }

    private func greyToast(for page: WatchedPage) -> Toast {
        Toast(pageID: page.id, pageName: page.name, body: "Unreachable", severity: .grey)
    }

    private func apply(_ toasts: [Toast], pages: [WatchedPage], showingLost: inout Bool) -> [Toast] {
        var pending: Set<UUID> = []
        return NetworkToast.apply(toasts, pages: pages, showingLost: &showingLost, pending: &pending)
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
