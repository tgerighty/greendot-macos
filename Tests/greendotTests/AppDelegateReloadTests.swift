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
