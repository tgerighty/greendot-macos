import Foundation
import XCTest
@testable import StatusCore
import TestSupport

final class MonitorFirstRunTests: XCTestCase {
    func testConcurrentFirstRunCallsEnableLaunchAtLoginOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        try store.save(AppConfig(didSetLaunchAtLogin: false))
        let transitionLock = ControllableLock()
        let monitor = Monitor(
            store: store,
            client: MapHTTPClient(),
            transitionLock: transitionLock
        )
        try monitor.load()

        let callbackLock = NSLock()
        var callbackCount = 0
        let firstCallback = expectation(description: "first launch-at-login callback")
        monitor.onLaunchAtLoginEnable = {
            callbackLock.lock()
            callbackCount += 1
            let isFirst = callbackCount == 1
            callbackLock.unlock()
            if isFirst { firstCallback.fulfill() }
        }

        transitionLock.blockNextAcquisition()
        let firstCall = DispatchWorkItem { monitor.enableLaunchAtLoginOnFirstRun() }
        DispatchQueue.global().async(execute: firstCall)
        XCTAssertTrue(transitionLock.waitUntilAcquisitionBlocked())

        let secondCall = expectation(description: "second first-run call completes")
        DispatchQueue.global().async {
            monitor.enableLaunchAtLoginOnFirstRun()
            secondCall.fulfill()
        }
        wait(for: [firstCallback, secondCall], timeout: 2)
        transitionLock.resumeBlockedAcquisition()
        firstCall.wait()

        callbackLock.lock()
        let finalCallbackCount = callbackCount
        callbackLock.unlock()
        XCTAssertEqual(finalCallbackCount, 1)
        XCTAssertTrue(try store.load().didSetLaunchAtLogin)
    }

    func testFirstRunSaveFailureDoesNotEnableLaunchAtLogin() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PageStore(directory: directory)
        let initialConfig = AppConfig(didSetLaunchAtLogin: false)
        try store.save(initialConfig)
        let originalData = try Data(contentsOf: store.configURL)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()

        try FileManager.default.removeItem(at: store.configURL)
        try FileManager.default.createDirectory(at: store.configURL, withIntermediateDirectories: true)
        var callbackCount = 0
        monitor.onLaunchAtLoginEnable = { callbackCount += 1 }

        monitor.enableLaunchAtLoginOnFirstRun()
        XCTAssertEqual(callbackCount, 0)
        XCTAssertThrowsError(try store.load())

        try FileManager.default.removeItem(at: store.configURL)
        try originalData.write(to: store.configURL)
        let persisted = try store.load()
        XCTAssertFalse(persisted.didSetLaunchAtLogin)

        monitor.enableLaunchAtLoginOnFirstRun()
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(try store.load().didSetLaunchAtLogin)

        monitor.enableLaunchAtLoginOnFirstRun()
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(try store.load().didSetLaunchAtLogin)
    }
}
