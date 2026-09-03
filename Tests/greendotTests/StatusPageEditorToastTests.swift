import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class StatusPageEditorToastTests: XCTestCase {
    private let redJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [{"name": "API", "status": "major_outage", "group": false}],
      "incidents": []
    }
    """

    private let twoComponentJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [
        {"name": "API", "status": "major_outage", "group": false},
        {"name": "Web", "status": "operational", "group": false}
      ],
      "incidents": []
    }
    """

    private let redAndYellowJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "major"},
      "components": [
        {"name": "API", "status": "major_outage", "group": false},
        {"name": "Web", "status": "degraded_performance", "group": false}
      ],
      "incidents": []
    }
    """

    func testSuccessfulComponentToggleClearsToast() async throws {
        let seed = try await seededEditorMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        var cleared: [UUID] = []
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: pageID,
            onChange: {},
            presentError: { error in XCTFail("unexpected error: \(error)") },
            clearToast: { cleared.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.button("component-API", in: Self.panelView())).performClick(nil)

        XCTAssertEqual(cleared, [pageID])
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)
    }

    func testSuccessfulSetAllClearsToast() async throws {
        let seed = try await seededEditorMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        var cleared: [UUID] = []
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: pageID,
            onChange: {},
            presentError: { error in XCTFail("unexpected error: \(error)") },
            clearToast: { cleared.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.button("component-all", in: Self.panelView())).performClick(nil)

        XCTAssertEqual(cleared, [pageID])
        XCTAssertEqual(monitor.pages[0].displaySeverity, .green)
    }

    func testHealthySiblingToggleDoesNotClearToastWhilePageStaysRed() async throws {
        let seed = try await seededEditorMonitor(json: twoComponentJSON)
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        var cleared: [UUID] = []
        var refreshed: [UUID] = []
        let editor = StatusPageEditor(
            monitor: seed.monitor,
            editingPageID: seed.pageID,
            onChange: {},
            presentError: { error in XCTFail("unexpected error: \(error)") },
            clearToast: { cleared.append($0) },
            refreshToast: { refreshed.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.button("component-Web", in: Self.panelView())).performClick(nil)

        XCTAssertTrue(cleared.isEmpty)
        XCTAssertTrue(refreshed.isEmpty)
        XCTAssertEqual(seed.monitor.pages[0].displaySeverity, .red)
    }

    func testRedToYellowFilterChangeRefreshesToast() async throws {
        let seed = try await seededEditorMonitor(json: redAndYellowJSON)
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        var cleared: [UUID] = []
        var refreshed: [UUID] = []
        let editor = StatusPageEditor(
            monitor: seed.monitor,
            editingPageID: seed.pageID,
            onChange: {},
            presentError: { error in XCTFail("unexpected error: \(error)") },
            clearToast: { cleared.append($0) },
            refreshToast: { refreshed.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.button("component-API", in: Self.panelView())).performClick(nil)

        XCTAssertTrue(cleared.isEmpty)
        XCTAssertEqual(refreshed, [seed.pageID])
        XCTAssertEqual(seed.monitor.pages[0].displaySeverity, .yellow)
    }

    func testSavingRedPageWithSameURLDoesNotRecreateToast() async throws {
        let seed = try await seededEditorMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        var cleared: [UUID] = []
        var refreshed: [UUID] = []
        var changed = 0
        let editor = StatusPageEditor(
            monitor: seed.monitor,
            editingPageID: seed.pageID,
            onChange: { changed += 1 },
            presentError: { error in XCTFail("unexpected error: \(error)") },
            clearToast: { cleared.append($0) },
            refreshToast: { refreshed.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.field("name-field", in: Self.panelView())).stringValue = "Renamed"
        try XCTUnwrap(Self.button("save-button", in: Self.panelView())).performClick(nil)
        for _ in 0..<100 where changed == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(changed, 1)
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertTrue(refreshed.isEmpty)
        XCTAssertEqual(seed.monitor.pages[0].displaySeverity, .red)
    }

    func testFailedComponentToggleDoesNotClearToast() async throws {
        let seed = try await seededEditorMonitor()
        defer { try? FileManager.default.removeItem(at: seed.directory) }
        let monitor = seed.monitor
        let pageID = seed.pageID
        try breakPersistence(at: seed.directory.appendingPathComponent("config.json"))
        var cleared: [UUID] = []
        var presented = 0
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: pageID,
            onChange: { XCTFail("failed toggle must not report a change") },
            presentError: { _ in presented += 1 },
            clearToast: { cleared.append($0) }
        )
        editor.show()
        defer { editor.close() }

        try XCTUnwrap(Self.button("component-API", in: Self.panelView())).performClick(nil)

        XCTAssertEqual(presented, 1)
        XCTAssertTrue(cleared.isEmpty)
    }

    private struct Seed {
        let monitor: Monitor
        let pageID: UUID
        let directory: URL
    }

    private func seededEditorMonitor(json: String? = nil) async throws -> Seed {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = PageStore(directory: directory)
        let body = json ?? redJSON
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(body.utf8), 200)
            ])
        )
        try monitor.load()
        try await monitor.add(
            url: XCTUnwrap(URL(string: "https://www.githubstatus.com")),
            name: "GitHub"
        )
        let pageID = try XCTUnwrap(monitor.pages.first?.id)
        XCTAssertEqual(monitor.pages[0].displaySeverity, .red)
        return Seed(monitor: monitor, pageID: pageID, directory: directory)
    }

    private static func panelView() -> NSView? {
        NSApp.windows.first {
            $0.accessibilityIdentifier() == "status-page-panel" && $0.isVisible
        }?.contentView
    }

    private static func button(_ identifier: String, in view: NSView?) -> NSButton? {
        findView(NSButton.self, identifier: identifier, in: view)
    }

    private static func field(_ identifier: String, in view: NSView?) -> NSTextField? {
        findView(NSTextField.self, identifier: identifier, in: view)
    }

    private static func findView<T: NSView>(
        _ type: T.Type,
        identifier: String,
        in view: NSView?
    ) -> T? {
        guard let view else { return nil }
        if let match = view as? T, match.accessibilityIdentifier() == identifier {
            return match
        }
        for child in view.subviews {
            if let match = findView(type, identifier: identifier, in: child) { return match }
        }
        return nil
    }
}
