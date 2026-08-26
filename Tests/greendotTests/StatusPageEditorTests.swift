import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class StatusPageEditorTests: XCTestCase {
    private let statuspageJSON = """
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """

    func testFailedAddKeepsEditorOpenAndRetainsEnteredValues() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let pageURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
            ])
        )
        try monitor.load()
        try breakPersistence(at: store.configURL)

        let errorPresented = expectation(description: "the add error is presented")
        var presentedErrors = 0
        var onChangeCount = 0
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: UUID?.none,
            onChange: { onChangeCount += 1 },
            presentError: { _ in
                presentedErrors += 1
                errorPresented.fulfill()
            }
        )
        editor.show()
        defer { editor.close() }

        let panel = try XCTUnwrap(Self.visiblePanelWindow())
        let enteredURL = pageURL.absoluteString
        let enteredName = "GitHub production"
        try XCTUnwrap(Self.field("url-field", in: panel.contentView)).stringValue = enteredURL
        try XCTUnwrap(Self.field("name-field", in: panel.contentView)).stringValue = enteredName
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)

        await fulfillment(of: [errorPresented], timeout: 2)

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(Self.field("url-field", in: panel.contentView)?.stringValue, enteredURL)
        XCTAssertEqual(Self.field("name-field", in: panel.contentView)?.stringValue, enteredName)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(onChangeCount, 0)
        XCTAssertTrue(monitor.pages.isEmpty)
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.configURL.path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)
        try FileManager.default.removeItem(at: store.configURL)
        XCTAssertTrue(try store.load().pages.isEmpty)
    }

    func testFailedEditKeepsEditorOpenAndRetainsEnteredValues() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let originalURL = try XCTUnwrap(URL(string: "https://www.githubstatus.com"))
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
            ])
        )
        try monitor.load()
        try await monitor.add(url: originalURL, name: "GitHub")
        let before = try XCTUnwrap(monitor.pages.first)
        let originalConfig = try Data(contentsOf: store.configURL)
        try breakPersistence(at: store.configURL)

        let errorPresented = expectation(description: "the edit error is presented")
        var presentedErrors = 0
        var onChangeCount = 0
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: before.id,
            onChange: { onChangeCount += 1 },
            presentError: { _ in
                presentedErrors += 1
                errorPresented.fulfill()
            }
        )
        editor.show()
        defer { editor.close() }

        let panel = try XCTUnwrap(Self.visiblePanelWindow())
        let editedURL = "https://status.example.com"
        let editedName = "Edited production status"
        try XCTUnwrap(Self.field("url-field", in: panel.contentView)).stringValue = editedURL
        try XCTUnwrap(Self.field("name-field", in: panel.contentView)).stringValue = editedName
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)

        await fulfillment(of: [errorPresented], timeout: 2)

        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(Self.field("url-field", in: panel.contentView)?.stringValue, editedURL)
        XCTAssertEqual(Self.field("name-field", in: panel.contentView)?.stringValue, editedName)
        XCTAssertEqual(presentedErrors, 1)
        XCTAssertEqual(onChangeCount, 0)
        XCTAssertEqual(monitor.pages, [before])

        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.configURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        try FileManager.default.removeItem(at: store.configURL)
        try originalConfig.write(to: store.configURL)
        XCTAssertEqual(try store.load().pages, [before])
    }

    func testStaleEditorPageIDPresentsTypedErrorAndDoesNotShowPanel() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        let staleID = UUID()
        var presentedError: Error?
        let editor = StatusPageEditor(
            monitor: monitor,
            editingPageID: staleID,
            onChange: { XCTFail("A stale editor must not report a change") },
            presentError: { presentedError = $0 }
        )

        editor.show()
        defer { editor.close() }

        XCTAssertEqual(presentedError as? MonitorError, .pageNotFound(staleID))
        XCTAssertNil(Self.visiblePanelWindow())
    }

    func testReplacingEditorsAcrossRunLoopTurnsKeepsTheLatestPanelVisible() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = Monitor(
            store: PageStore(directory: directory),
            client: MapHTTPClient(byPath: [
                "/api/v2/summary.json": (Data(statuspageJSON.utf8), 200)
            ])
        )
        try monitor.load()
        try await monitor.add(url: XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "First")
        try await monitor.add(url: XCTUnwrap(URL(string: "https://www.githubstatus.com")), name: "Second")

        var current: StatusPageEditor?
        defer { current?.close() }
        for index in 0..<10 {
            let previous = current
            previous?.close()
            let page = monitor.pages[index % monitor.pages.count]
            let replacement = StatusPageEditor(
                monitor: monitor,
                editingPageID: page.id,
                onChange: { XCTFail("Showing an editor must not report a change") },
                presentError: { error in XCTFail("unexpected error: \(error)") }
            )
            let shown = expectation(description: "replacement editor \(index) is shown")
            DispatchQueue.main.async {
                withExtendedLifetime(previous) {
                    replacement.show()
                }
                shown.fulfill()
            }

            await fulfillment(of: [shown], timeout: 2)
            XCTAssertEqual(Self.visiblePanelWindow()?.title, "Edit Status Page")
            current = replacement
        }
    }

    func testSecondSaveWhilePendingInvokesOnSaveOnceAndClosesAfterSuccess() async throws {
        _ = NSApplication.shared
        let gate = PendingSaveGate()
        addTeardownBlock { await gate.complete(with: false) }
        let panelController = PagePanelController(
            page: nil,
            onSave: { _, _ in await gate.save() }
        )
        panelController.show()
        defer { panelController.close() }

        let panel = try XCTUnwrap(Self.visiblePanelWindow())
        XCTAssertEqual(Self.field("url-field", in: panel.contentView)?.stringValue, "")
        try XCTUnwrap(Self.field("url-field", in: panel.contentView)).stringValue = "https://status.example.com"
        try XCTUnwrap(Self.field("name-field", in: panel.contentView)).stringValue = "Pending save"
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)
        await gate.waitUntilStarted()

        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)
        let callsBeforeCompletion = await gate.callCount()
        XCTAssertEqual(callsBeforeCompletion, 1)
        XCTAssertTrue(panel.isVisible)

        await gate.complete(with: true)
        await waitUntilHidden(panel)
        XCTAssertFalse(panel.isVisible)
        let callsAfterCompletion = await gate.callCount()
        XCTAssertEqual(callsAfterCompletion, 1)
    }

    func testCancelWhileSavePendingClosesPanelAndIgnoresLateSuccess() async throws {
        _ = NSApplication.shared
        let gate = PendingSaveGate()
        addTeardownBlock { await gate.complete(with: false) }
        let panelController = PagePanelController(
            page: nil,
            onSave: { _, _ in await gate.save() }
        )
        panelController.show()
        defer { panelController.close() }

        let panel = try XCTUnwrap(Self.visiblePanelWindow())
        try XCTUnwrap(Self.field("url-field", in: panel.contentView)).stringValue = "https://status.example.com"
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)
        await gate.waitUntilStarted()
        XCTAssertTrue(panel.isVisible)

        try XCTUnwrap(Self.button("cancel-button", in: panel.contentView)).performClick(nil)
        await waitUntilHidden(panel)
        XCTAssertFalse(panel.isVisible)

        await gate.complete(with: true)
        await waitUntilHidden(panel)
        XCTAssertFalse(panel.isVisible)
        let calls = await gate.callCount()
        XCTAssertEqual(calls, 1)
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

    private static func field(_ identifier: String, in view: NSView?) -> NSTextField? {
        findView(NSTextField.self, identifier: identifier, in: view)
    }

    private static func button(_ identifier: String, in view: NSView?) -> NSButton? {
        findView(NSButton.self, identifier: identifier, in: view)
    }

    private static func visiblePanelWindow() -> NSWindow? {
        NSApp.windows.first {
            $0.accessibilityIdentifier() == "status-page-panel" && $0.isVisible
        }
    }

    private func waitUntilHidden(_ window: NSWindow) async {
        for _ in 0..<100 {
            if !window.isVisible { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func breakPersistence(at configURL: URL) throws {
        try? FileManager.default.removeItem(at: configURL)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
    }
}

extension StatusPageEditorTests {
    func testFieldsAreDisabledWhileSavePendingAndRestoredAfterFailure() async throws {
        _ = NSApplication.shared
        let gate = PendingSaveGate()
        addTeardownBlock { await gate.complete(with: false) }
        let panelController = PagePanelController(
            page: nil,
            onSave: { _, _ in await gate.save() }
        )
        panelController.show()
        defer { panelController.close() }

        let panel = try XCTUnwrap(Self.visiblePanelWindow())
        let urlField = try XCTUnwrap(Self.field("url-field", in: panel.contentView))
        let nameField = try XCTUnwrap(Self.field("name-field", in: panel.contentView))
        urlField.stringValue = "https://status.example.com"
        nameField.stringValue = "Pending save"
        try XCTUnwrap(Self.button("save-button", in: panel.contentView)).performClick(nil)
        await gate.waitUntilStarted()

        XCTAssertFalse(urlField.isEnabled)
        XCTAssertFalse(nameField.isEnabled)

        await gate.complete(with: false)
        await waitUntilFieldsEnabled(urlField, nameField)

        XCTAssertTrue(urlField.isEnabled)
        XCTAssertTrue(nameField.isEnabled)
        XCTAssertTrue(panel.isVisible)
    }

    private func waitUntilFieldsEnabled(_ fields: NSTextField...) async {
        for _ in 0..<100 {
            if fields.allSatisfy(\.isEnabled) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private actor PendingSaveGate {
    private var calls = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<Bool, Never>?

    func save() async -> Bool {
        calls += 1
        startedContinuation?.resume()
        startedContinuation = nil
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard calls == 0 else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func callCount() -> Int {
        calls
    }

    func complete(with result: Bool) {
        resultContinuation?.resume(returning: result)
        resultContinuation = nil
    }
}
