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
        let previous = [page("A", .green), page("B", .green)]
        let current = [page("A", .grey), page("B", .grey)]
        let pageToasts = [toast(current[0], .grey), toast(current[1], .grey)]

        XCTAssertEqual(NetworkToast.apply(pageToasts, previous: previous, current: current), [NetworkToast.lost])
    }

    func testRecoveryReplacesGreenToastsAndKeepsOthers() {
        let previous = [page("A", .grey), page("B", .grey)]
        let current = [page("A", .green), page("B", .red)]
        let pageToasts = [toast(current[0], .green), toast(current[1], .red)]

        XCTAssertEqual(
            NetworkToast.apply(pageToasts, previous: previous, current: current),
            [NetworkToast.regained, pageToasts[1]]
        )
    }

    func testSingleUnreachablePageKeepsItsOwnToast() {
        let previous = [page("A", .green)]
        let current = [page("A", .grey)]
        let pageToasts = [toast(current[0], .grey)]

        XCTAssertEqual(NetworkToast.apply(pageToasts, previous: previous, current: current), pageToasts)
    }

    func testPartialOutageKeepsPageToasts() {
        let previous = [page("A", .green), page("B", .green)]
        let current = [page("A", .grey), page("B", .green)]
        let pageToasts = [toast(current[0], .grey)]

        XCTAssertEqual(NetworkToast.apply(pageToasts, previous: previous, current: current), pageToasts)
    }

    func testStayingOfflineEmitsNothing() {
        let previous = [page("A", .grey), page("B", .grey)]
        let current = [page("A", .grey), page("B", .grey)]

        XCTAssertEqual(NetworkToast.apply([], previous: previous, current: current), [])
    }

    func testAllPagesMutedSuppressesNetworkToast() {
        let previous = [page("A", .green, muted: true), page("B", .green, muted: true)]
        let current = [page("A", .grey, muted: true), page("B", .grey, muted: true)]

        XCTAssertEqual(NetworkToast.apply([], previous: previous, current: current), [])
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

        let offline = Monitor(store: store, client: MapHTTPClient())
        try offline.load()
        let lost = try await offline.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])

        let online = Monitor(
            store: store,
            client: MapHTTPClient(byPath: ["/api/v2/summary.json": (greenJSON, 200)])
        )
        try online.load()
        let regained = try await online.pollAll()
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
