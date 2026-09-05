import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class AppDelegateReloadTests: XCTestCase {
    func testReloadConfigClosesEditorAndDropsItsPendingSave() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(AppConfig())
        let client = ControllableHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { client.failAll() }
        defer { delegate.editor?.close() }
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        delegate.openEditor(editingPageID: nil)
        let opened = await waitForPanel()
        let panel = try XCTUnwrap(opened)
        try XCTUnwrap(Self.field("url-field", in: panel.contentView)).stringValue = "https://status.openai.com"
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)
        await client.waitUntilRequestCount(1)

        var imported = AppConfig()
        imported.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "GitHub")
        ]
        try store.save(imported)

        delegate.reloadConfig()
        client.complete(request: 1, with: Data(Self.openAISummaryJSON.utf8))
        await settle()

        XCTAssertNil(delegate.editor)
        XCTAssertFalse(panel.isVisible)
        XCTAssertEqual(monitor.pages.map(\.name), ["GitHub"])
        XCTAssertEqual(try store.load().pages.map(\.name), ["GitHub"])
        XCTAssertNil(presented)
    }

    func testFailedReloadDoesNotLetAPollOverwriteTheFile() async throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [
            WatchedPage(url: try XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "GitHub")
        ]
        try store.save(config)
        let client = ControllableHTTPClient()
        let monitor = Monitor(store: store, client: client)
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        defer { client.failAll() }
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { _ in }

        let poll = Task { await delegate.pollAndRefresh(monitor) }
        await client.waitUntilRequestCount(1)
        let corrupt = Data("{".utf8)
        try corrupt.write(to: store.configURL)
        delegate.reloadConfig()
        client.complete(request: 1, with: Data(Self.githubSummaryJSON.utf8))
        await poll.value

        XCTAssertEqual(try Data(contentsOf: store.configURL), corrupt)
        XCTAssertNil(delegate.pollTimer)
        XCTAssertTrue(delegate.configLoadFailed)

        try store.save(config)
        delegate.reloadConfig()

        XCTAssertFalse(delegate.configLoadFailed)
        XCTAssertNotNil(delegate.pollTimer)
    }

    func testReloadConfigClearsToastsForRemovedAndMutedPages() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let pageA = WatchedPage(url: try XCTUnwrap(URL(string: "https://a.example.com")), name: "A")
        let pageB = WatchedPage(url: try XCTUnwrap(URL(string: "https://b.example.com")), name: "B")
        var config = AppConfig()
        config.pages = [pageA, pageB]
        try store.save(config)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        var mutedB = pageB
        mutedB.notificationsEnabled = false
        let pageC = WatchedPage(url: try XCTUnwrap(URL(string: "https://c.example.com")), name: "C")
        var next = AppConfig()
        next.pages = [mutedB, pageC]
        try store.save(next)

        delegate.reloadConfig()

        XCTAssertNil(presented)
        XCTAssertEqual(monitor.pages.map(\.name), ["B", "C"])
        XCTAssertTrue(delivery.clearedPageIDs.contains(pageA.id))
        XCTAssertTrue(delivery.clearedPageIDs.contains(pageB.id))
        XCTAssertFalse(delivery.clearedPageIDs.contains(pageC.id))
    }

    func testReloadConfigKeepsClosedEditorAliveUntilNextRunLoopTurn() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(AppConfig())
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { XCTFail("unexpected error: \($0)") }

        weak var weakEditor: StatusPageEditor?
        autoreleasepool {
            delegate.openEditor(editingPageID: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            weakEditor = delegate.editor
            XCTAssertNotNil(weakEditor, "Editor must exist before the reload")

            delegate.reloadConfig()

            XCTAssertNil(delegate.editor)
            XCTAssertNotNil(weakEditor, "Editor must stay alive during the menu action")
        }

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(weakEditor, "Editor must be released on the next run-loop turn")
    }

    private static let githubSummaryJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    private static let openAISummaryJSON = """
    {
      "page": {"name": "OpenAI", "url": "https://status.openai.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    private func waitForPanel() async -> NSWindow? {
        for _ in 0..<200 {
            if let panel = Self.visiblePanelWindow() { return panel }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return nil
    }

    /// Gives a cancelled save task time to finish writing, so a leak would be visible.
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private static func visiblePanelWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.accessibilityIdentifier() == "status-page-panel" && $0.isVisible
        }
    }

    private static func findView<T: NSView>(_ type: T.Type, identifier: String, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T, match.accessibilityIdentifier() == identifier {
            return match
        }
        for child in view.subviews {
            if let match = findView(type, identifier: identifier, in: child) { return match }
        }
        return nil
    }

    private static func field(_ identifier: String, in view: NSView?) -> NSTextField? {
        findView(NSTextField.self, identifier: identifier, in: view)
    }

    private static func button(_ identifier: String, in view: NSView?) -> NSButton? {
        findView(NSButton.self, identifier: identifier, in: view)
    }
}

@MainActor
final class AppDelegateReloadToastTests: XCTestCase {
    private struct Fixture {
        let store: PageStore
        let monitor: Monitor
        let delegate: AppDelegate
        let delivery: InMemoryToastDelivery
    }

    func testReloadConfigClearsToastWhenPageURLChanges() throws {
        let page = try Self.redPage(components: [Self.component("API", .red)])
        let fixture = try makeFixture(page: page)
        defer { fixture.delegate.pollTimer?.invalidate() }
        var moved = page
        moved.url = try XCTUnwrap(URL(string: "https://moved.example.com"))
        try Self.writeConfig(pages: [moved], to: fixture.store)

        fixture.delegate.reloadConfig()

        XCTAssertTrue(fixture.delivery.clearedPageIDs.contains(page.id))
        XCTAssertTrue(fixture.delivery.toasts.isEmpty)
    }

    func testReloadConfigClearsToastWhenFilterMakesPageGreen() throws {
        let page = try Self.redPage(components: [
            Self.component("API", .red),
            Self.component("Web", .green)
        ])
        let fixture = try makeFixture(page: page)
        defer { fixture.delegate.pollTimer?.invalidate() }
        var filtered = page
        filtered.disabledComponentNames = ["API"]
        try Self.writeConfig(pages: [filtered], to: fixture.store)

        fixture.delegate.reloadConfig()

        XCTAssertEqual(fixture.monitor.pages.first?.displaySeverity, .green)
        XCTAssertTrue(fixture.delivery.clearedPageIDs.contains(page.id))
    }

    func testReloadConfigRefreshesToastWhenSeverityChangesButStaysUnhealthy() throws {
        let page = try Self.redPage(components: [
            Self.component("API", .red),
            Self.component("Web", .yellow)
        ])
        let fixture = try makeFixture(page: page)
        defer { fixture.delegate.pollTimer?.invalidate() }
        var filtered = page
        filtered.disabledComponentNames = ["API"]
        try Self.writeConfig(pages: [filtered], to: fixture.store)

        fixture.delegate.reloadConfig()

        XCTAssertEqual(fixture.delivery.toasts.map(\.pageID), [page.id])
        XCTAssertEqual(fixture.delivery.toasts.first?.severity, .yellow)
        XCTAssertFalse(fixture.delivery.clearedPageIDs.contains(page.id))
    }

    func testReloadConfigKeepsToastWhenPageIsUnchanged() throws {
        let page = try Self.redPage(components: [Self.component("API", .red)])
        let fixture = try makeFixture(page: page)
        defer { fixture.delegate.pollTimer?.invalidate() }
        try Self.writeConfig(pages: [page], to: fixture.store)

        fixture.delegate.reloadConfig()

        XCTAssertEqual(fixture.monitor.pages.first?.displaySeverity, .red)
        XCTAssertFalse(fixture.delivery.clearedPageIDs.contains(page.id))
        XCTAssertTrue(fixture.delivery.toasts.isEmpty)
    }

    func testReloadConfigRefreshesToastWhenPageIsRenamed() throws {
        let page = try Self.redPage(components: [Self.component("API", .red)])
        let fixture = try makeFixture(page: page)
        defer { fixture.delegate.pollTimer?.invalidate() }
        var renamed = page
        renamed.name = "Renamed"
        try Self.writeConfig(pages: [renamed], to: fixture.store)

        fixture.delegate.reloadConfig()

        XCTAssertEqual(fixture.delivery.toasts.map(\.pageID), [page.id])
        XCTAssertEqual(fixture.delivery.toasts.first?.pageName, "Renamed")
        XCTAssertEqual(fixture.delivery.toasts.first?.severity, .red)
        XCTAssertFalse(fixture.delivery.clearedPageIDs.contains(page.id))
    }

    private func makeFixture(page: WatchedPage) throws -> Fixture {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        var config = AppConfig()
        config.pages = [page]
        try store.save(config)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let delivery = InMemoryToastDelivery()
        let delegate = AppDelegate(toastDelivery: delivery)
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { XCTFail("unexpected error: \($0)") }
        return Fixture(store: store, monitor: monitor, delegate: delegate, delivery: delivery)
    }

    /// Writes config.json only. state.json keeps its cached snapshot, as a hand edit does.
    private static func writeConfig(pages: [WatchedPage], to store: PageStore) throws {
        var config = AppConfig()
        config.pages = pages
        try JSONEncoder().encode(config).write(to: store.configURL, options: .atomic)
    }

    private static func redPage(components: [ComponentStatus]) throws -> WatchedPage {
        let url = try XCTUnwrap(URL(string: "https://a.example.com"))
        return WatchedPage(
            url: url,
            name: "A",
            snapshot: PageSnapshot(
                name: "A",
                url: url,
                provider: .statuspage,
                overall: .red,
                components: components,
                incidents: [],
                isUnreachable: false
            )
        )
    }

    private static func component(_ name: String, _ severity: Severity) -> ComponentStatus {
        ComponentStatus(name: name, severity: severity, statusText: severity.displayName)
    }
}

@MainActor
final class AppDelegateFailedReloadTests: XCTestCase {
    private var presented: Error?

    func testFailedReloadBlocksMenuMutationsUntilReloadSucceeds() throws {
        let (store, delegate) = try failedReloadFixture()
        defer { delegate.pollTimer?.invalidate() }
        let monitor = try XCTUnwrap(delegate.monitor)
        let pageID = monitor.pages[0].id
        XCTAssertFalse(delegate.performStoreChange { try monitor.remove(id: pageID) })
        XCTAssertTrue(presented is ConfigMenuError)
        XCTAssertEqual(monitor.pages.count, 1)
        XCTAssertEqual(try Data(contentsOf: store.configURL), Data("{".utf8))
        try store.save(AppConfig(pages: monitor.pages))
        delegate.reloadConfig()
        XCTAssertFalse(delegate.configLoadFailed)
        XCTAssertTrue(delegate.performStoreChange { try monitor.toggleNotifications(id: pageID) })
    }

    func testFailedReloadRefusesToOpenEditor() throws {
        let (_, delegate) = try failedReloadFixture()
        defer { delegate.pollTimer?.invalidate() }
        defer { delegate.editor?.close() }
        delegate.openEditor(editingPageID: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertNil(delegate.editor)
        XCTAssertTrue(presented is ConfigMenuError)
    }

    /// Seeds one page, corrupts config.json, then reloads, so the failure flag is set.
    private func failedReloadFixture() throws -> (PageStore, AppDelegate) {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        let page = WatchedPage(url: try XCTUnwrap(URL(string: "https://a.example.com")), name: "A")
        try store.save(AppConfig(pages: [page]))
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { [weak self] in self?.presented = $0 }
        try Data("{".utf8).write(to: store.configURL)
        delegate.reloadConfig()
        XCTAssertTrue(delegate.configLoadFailed)
        presented = nil
        return (store, delegate)
    }
}
