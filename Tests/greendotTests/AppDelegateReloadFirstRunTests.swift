import AppKit
import StatusCore
import XCTest
@testable import greendot
import TestSupport

@MainActor
final class AppDelegateReloadFirstRunTests: XCTestCase {
    func testSuccessfulReloadAfterFailedLaunchLoadRunsFirstRunSetup() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] != nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.configURL)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        var enableCount = 0
        monitor.onLaunchAtLoginEnable = { enableCount += 1 }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        var presented: Error?
        delegate.presentError = { presented = $0 }

        XCTAssertFalse(delegate.loadMonitor(monitor))
        delegate.configLoadFailed = true
        XCTAssertNotNil(presented)

        try store.save(AppConfig())
        delegate.reloadConfig()

        XCTAssertEqual(enableCount, 1)
        XCTAssertTrue(try store.load().didSetLaunchAtLogin)
        XCTAssertFalse(delegate.configLoadFailed)
    }

    func testReloadDoesNotRepeatFirstRunSetup() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["GREENDOT_SKIP_LOGIN_ITEM"] != nil)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PageStore(directory: dir)
        try store.save(AppConfig(didSetLaunchAtLogin: true))
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        var enableCount = 0
        monitor.onLaunchAtLoginEnable = { enableCount += 1 }
        let delegate = AppDelegate(toastDelivery: InMemoryToastDelivery())
        defer { delegate.pollTimer?.invalidate() }
        delegate.store = store
        delegate.monitor = monitor
        delegate.presentError = { _ in }

        delegate.reloadConfig()

        XCTAssertEqual(enableCount, 0)
        XCTAssertFalse(delegate.configLoadFailed)
    }
}
