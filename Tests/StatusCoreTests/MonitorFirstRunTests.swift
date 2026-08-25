import XCTest
@testable import StatusCore

final class MonitorFirstRunTests: XCTestCase {
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
    }
}
