import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class PanelLifecycleTests: XCTestCase {
    func testReplacingEditPanelDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        var panel: PagePanelController? = PagePanelController(page: page, onSave: { _, _ in true })
        panel?.show()
        panel?.close()
        panel = PagePanelController(page: page, onSave: { _, _ in true })
        panel?.show()
        panel?.close()
        panel = nil
    }

    func testCloseAfterWindowCloseDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(page: page, onSave: { _, _ in true })
        panel.show()
        panel.closeWindow()
        panel.close()
    }

    func testReplacingEditPanelFiveTimesDoesNotCrash() {
        _ = NSApplication.shared
        let first = Self.nestedPage(name: "OpenAI")
        let second = Self.nestedPage(name: "Box")
        var panel: PagePanelController?
        for _ in 1...5 {
            panel?.close()
            panel = PagePanelController(page: first, onSave: { _, _ in true })
            panel?.show()
            panel?.close()
            panel = PagePanelController(page: second, onSave: { _, _ in true })
            panel?.show()
        }
        panel?.close()
        panel = nil
    }

    func testUITestDriverTogglesEveryComponentFiveTimes() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(
            page: page,
            onSave: { _, _ in true },
            onToggleComponent: { _ in true },
            onSetAll: { _ in true }
        )
        panel.show()
        let ids = UITestDriver.identifiers().filter { $0.hasPrefix("component-") && $0 != "component-list" }
        XCTAssertGreaterThanOrEqual(ids.count, 21)
        for _ in 1...5 {
            for identifier in ids {
                XCTAssertTrue(UITestDriver.clickIdentifier(identifier), identifier)
            }
        }
        panel.close()
    }

    func testClickingEveryComponentFiveTimesDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(
            page: page,
            onSave: { _, _ in true },
            onToggleComponent: { _ in true },
            onSetAll: { _ in true }
        )
        panel.show()
        let window = NSApp.windows.first { $0.title == "Edit Status Page" }
        XCTAssertNotNil(window)
        let boxes = Self.checkboxes(in: window?.contentView)
        XCTAssertGreaterThanOrEqual(boxes.count, 21)
        for _ in 1...5 {
            for box in boxes {
                box.performClick(nil)
            }
        }
        panel.close()
    }

    func testFailedPersistLeavesCheckboxesUnchanged() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(
            page: page,
            onSave: { _, _ in true },
            onToggleComponent: { _ in false },
            onSetAll: { _ in false }
        )
        panel.show()
        let window = NSApp.windows.first { $0.title == "Edit Status Page" }
        let boxes = Self.checkboxes(in: window?.contentView)
        XCTAssertGreaterThanOrEqual(boxes.count, 21)
        let before = boxes.map(\.state)
        for box in boxes {
            box.performClick(nil)
        }
        XCTAssertEqual(boxes.map(\.state), before)
        panel.close()
    }

    func testStatusDotImageIsNonNilAndHasSize() {
        _ = NSApplication.shared
        let image = StatusDot.image(.green, size: 12)
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, NSSize(width: 12, height: 12))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testStatusDotImageUsesRequestedSize() {
        _ = NSApplication.shared
        for severity in [Severity.green, .yellow, .red, .grey] {
            let image = StatusDot.image(severity, size: 14)
            XCTAssertNotNil(image)
            XCTAssertEqual(image.size.width, 14)
            XCTAssertEqual(image.size.height, 14)
        }
    }

    func testRepeatedStatusDotReusesImagePerSeverityAndSize() {
        _ = NSApplication.shared
        let green14a = StatusDot.image(.green, size: 14)
        let green14b = StatusDot.image(.green, size: 14)
        let red14 = StatusDot.image(.red, size: 14)
        let green12 = StatusDot.image(.green, size: 12)
        XCTAssertTrue(green14a === green14b)
        XCTAssertFalse(green14a === red14)
        XCTAssertFalse(green14a === green12)
        XCTAssertEqual(green14a.accessibilityDescription, Severity.green.rawValue)
        XCTAssertEqual(red14.accessibilityDescription, Severity.red.rawValue)
        XCTAssertEqual(green14a.size, NSSize(width: 14, height: 14))
        XCTAssertEqual(green12.size, NSSize(width: 12, height: 12))
    }

    func testPulseSkipsIconRefreshWhenNothingIsUnreachable() {
        XCTAssertEqual(
            GreyPulse.displayedSeverity(
                persistent: .green,
                hasUnreachable: true,
                now: Date(timeIntervalSince1970: 0)
            ),
            .grey
        )
        XCTAssertEqual(
            GreyPulse.displayedSeverity(
                persistent: .green,
                hasUnreachable: false,
                now: Date(timeIntervalSince1970: 0)
            ),
            .green
        )
    }

    func testShouldSeedOpenAIOnlyWhenLoadSucceededAndPagesEmpty() {
        XCTAssertTrue(AppDelegate.shouldSeedOpenAI(loadSucceeded: true, pagesEmpty: true, skipSeed: false))
        XCTAssertFalse(AppDelegate.shouldSeedOpenAI(loadSucceeded: false, pagesEmpty: true, skipSeed: false))
        XCTAssertFalse(AppDelegate.shouldSeedOpenAI(loadSucceeded: true, pagesEmpty: false, skipSeed: false))
        XCTAssertFalse(AppDelegate.shouldSeedOpenAI(loadSucceeded: true, pagesEmpty: true, skipSeed: true))
    }

    func testLoadMonitorPresentsCorruptStoreErrorAndLeavesFile() throws {
        let (dir, configURL) = try writeTempConfig(Data("{".utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = Monitor(store: PageStore(directory: dir), client: MapHTTPClient())
        let delegate = AppDelegate()
        var presented: Error?
        delegate.presentError = { presented = $0 }
        XCTAssertFalse(delegate.loadMonitor(monitor))
        XCTAssertEqual(presented as? StoreError, .corrupt)
        XCTAssertTrue(monitor.pages.isEmpty)
        XCTAssertEqual(try Data(contentsOf: configURL), Data("{".utf8))
    }

    func testLoadMonitorSucceedsWhenConfigIsMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = Monitor(store: PageStore(directory: dir), client: MapHTTPClient())
        let delegate = AppDelegate()
        var presented: Error?
        delegate.presentError = { presented = $0 }
        XCTAssertTrue(delegate.loadMonitor(monitor))
        XCTAssertNil(presented)
        XCTAssertTrue(monitor.pages.isEmpty)
    }

    func testPerformStoreChangePresentsSaveError() throws {
        let (dir, monitor) = try loadedMonitorWithPage()
        defer { try? FileManager.default.removeItem(at: dir) }
        try replaceConfigWithDirectory(in: dir)
        let delegate = AppDelegate()
        var presented = false
        delegate.presentError = { _ in presented = true }
        let id = monitor.pages[0].id
        XCTAssertFalse(delegate.performStoreChange { try monitor.remove(id: id) })
        XCTAssertTrue(presented)
        XCTAssertEqual(monitor.pages.count, 1)
    }

    func testPerformStoreChangeDoesNotPresentOnSuccess() throws {
        let (dir, monitor) = try loadedMonitorWithPage()
        defer { try? FileManager.default.removeItem(at: dir) }
        let delegate = AppDelegate()
        var presented = false
        delegate.presentError = { _ in presented = true }
        XCTAssertTrue(delegate.performStoreChange { try monitor.remove(id: monitor.pages[0].id) })
        XCTAssertFalse(presented)
        XCTAssertTrue(monitor.pages.isEmpty)
    }

    private static func checkboxes(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        var found: [NSButton] = []
        if let button = view as? NSButton {
            let identifier = button.accessibilityIdentifier()
            if identifier.hasPrefix("component-") {
                found.append(button)
            }
        }
        for child in view.subviews {
            found.append(contentsOf: checkboxes(in: child))
        }
        return found
    }

    private static func nestedPage(name: String = "Box") -> WatchedPage {
        let group = ComponentStatus(
            name: "Box Web Application",
            severity: .green,
            statusText: "Operational",
            id: "g1",
            children: (1...20).map { index in
                ComponentStatus(
                    name: "Child \(index)",
                    severity: index == 1 ? .red : .green,
                    statusText: "Operational",
                    id: "c\(index)"
                )
            },
            isGroup: true
        )
        return WatchedPage(
            url: URL(string: "https://status.box.com")!,
            name: name,
            snapshot: PageSnapshot(
                name: name,
                url: URL(string: "https://status.box.com")!,
                provider: .statuspage,
                overall: .green,
                components: [group],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}

extension PanelLifecycleTests {
    func testSeedFailureIsReportedWithoutFailingStartup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = Monitor(store: PageStore(directory: directory), client: MapHTTPClient())
        try monitor.load()
        let delegate = AppDelegate()
        var reported: Error?
        delegate.seedFailureDiagnostic = { reported = $0 }

        await delegate.maybeSeedOpenAI(monitor: monitor, loadSucceeded: true, skipSeed: false)

        XCTAssertEqual(reported as? ProbeError, .unsupported)
        XCTAssertTrue(monitor.pages.isEmpty)
    }

    func testSeedCancellationIsNotReported() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = Monitor(store: PageStore(directory: directory), client: CancellationHTTPClient())
        try monitor.load()
        let delegate = AppDelegate()
        var reported: Error?
        delegate.seedFailureDiagnostic = { reported = $0 }

        await delegate.maybeSeedOpenAI(monitor: monitor, loadSucceeded: true, skipSeed: false)

        XCTAssertNil(reported)
        XCTAssertTrue(monitor.pages.isEmpty)
    }
}

@MainActor
final class PanelReleaseTests: XCTestCase {
    func testClosingPanelDeallocatesControllerAndWindow() throws {
        _ = NSApplication.shared
        let controller = WeakReference<PagePanelController>()
        let window = WeakReference<NSWindow>()
        try autoreleasepool {
            let panel = PagePanelController(page: nil, onSave: { _, _ in true })
            controller.value = panel
            panel.show()
            window.value = try XCTUnwrap(NSApp.windows.first {
                $0.accessibilityIdentifier() == "status-page-panel" && $0.isVisible
            })
            panel.close()
        }

        let deadline = Date().addingTimeInterval(1)
        while controller.value != nil || window.value != nil, Date() < deadline {
            RunLoop.current.run(until: min(Date().addingTimeInterval(0.01), deadline))
        }

        XCTAssertNil(controller.value, "Timed out waiting for PagePanelController deallocation")
        XCTAssertNil(window.value, "Timed out waiting for status-page-panel window deallocation")
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?
}

private func writeTempConfig(_ data: Data) throws -> (URL, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let configURL = dir.appendingPathComponent("config.json")
    try data.write(to: configURL)
    return (dir, configURL)
}

private func loadedMonitorWithPage() throws -> (URL, Monitor) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PageStore(directory: dir)
    var config = AppConfig()
    config.pages = [WatchedPage(url: URL(string: "https://www.githubstatus.com")!, name: "GitHub")]
    try store.save(config)
    let monitor = Monitor(store: store, client: MapHTTPClient())
    try monitor.load()
    return (dir, monitor)
}

private func replaceConfigWithDirectory(in directory: URL) throws {
    let config = directory.appendingPathComponent("config.json")
    try FileManager.default.removeItem(at: config)
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
}

private struct CancellationHTTPClient: HTTPClient, Sendable {
    func get(_: URL) async throws -> (Data, Int) {
        throw CancellationError()
    }
}
