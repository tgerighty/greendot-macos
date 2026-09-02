import XCTest
import StatusCore
import TestSupport
@testable import greendot

@MainActor
final class AppDelegateToastClearTests: XCTestCase {
    private let greenJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    func testDisablingNotificationsClearsToast() async throws {
        let seed = try await seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)

        delegate.toggleNotifications(id: pageID, monitor: monitor)

        XCTAssertFalse(monitor.pages[0].notificationsEnabled)
        XCTAssertEqual(delivery.clearedPageIDs, [pageID])
    }

    func testEnablingNotificationsDoesNotClearToast() async throws {
        let seed = try await seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        try monitor.toggleNotifications(id: pageID)
        XCTAssertFalse(monitor.pages[0].notificationsEnabled)
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)

        delegate.toggleNotifications(id: pageID, monitor: monitor)

        XCTAssertTrue(monitor.pages[0].notificationsEnabled)
        XCTAssertTrue(delivery.clearedPageIDs.isEmpty)
    }

    func testFailedNotificationToggleDoesNotClearToast() async throws {
        let seed = try await seededMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        try breakPersistence(at: seed.directory.appendingPathComponent("config.json"))
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        var presented = 0
        delegate.presentError = { _ in presented += 1 }

        delegate.toggleNotifications(id: pageID, monitor: monitor)

        XCTAssertEqual(presented, 1)
        XCTAssertTrue(delivery.clearedPageIDs.isEmpty)
    }

    private struct Seed {
        let monitor: Monitor
        let pageID: UUID
        let directory: URL
    }

    private func seededMonitor() async throws -> Seed {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PageStore(directory: directory)
        let seed = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenJSON.utf8), 200)
            ])
        )
        try await seed.add(
            url: XCTUnwrap(URL(string: "https://www.githubstatus.com")),
            name: "GitHub"
        )
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(greenJSON.utf8), 200)
            ])
        )
        try monitor.load()
        let pageID = try XCTUnwrap(monitor.pages.first?.id)
        return Seed(monitor: monitor, pageID: pageID, directory: directory)
    }
}
