import XCTest
@testable import StatusCore

final class InterfaceStyleStoreTests: XCTestCase {
    func testSystemStyleIsOmittedFromBothFiles() throws {
        let store = try makeStore()
        var config = AppConfig(didSetLaunchAtLogin: true)
        config.pages = [try StateFileFixtures.page(name: "GitHub")]
        try store.save(config)

        let configText = try text(store.configURL)
        let stateText = try text(store.stateURL)
        XCTAssertFalse(configText.contains("interfaceStyle"), configText)
        XCTAssertFalse(stateText.contains("interfaceStyle"), stateText)
        XCTAssertEqual(try store.load().interfaceStyle, .system)
    }

    func testDarkStyleRoundTripsThroughStateFileOnly() throws {
        let store = try makeStore()
        var config = AppConfig(didSetLaunchAtLogin: true, interfaceStyle: .dark)
        config.pages = [try StateFileFixtures.page(name: "GitHub")]
        try store.save(config)

        XCTAssertFalse(try text(store.configURL).contains("interfaceStyle"))
        XCTAssertTrue(try text(store.stateURL).contains("\"interfaceStyle\" : \"dark\""))
        let loaded = try store.load()
        XCTAssertEqual(loaded.interfaceStyle, .dark)
        XCTAssertEqual(loaded.pages[0].snapshot?.overall, .green)
    }

    func testWrongStyleTypeKeepsTheCachedPoll() throws {
        let store = try makeStore()
        var config = AppConfig(didSetLaunchAtLogin: true, interfaceStyle: .light)
        config.pages = [try StateFileFixtures.page(name: "GitHub")]
        try store.save(config)

        var state = try text(store.stateURL)
        state = state.replacingOccurrences(of: "\"interfaceStyle\" : \"light\"", with: "\"interfaceStyle\" : 1")
        try Data(state.utf8).write(to: store.stateURL)

        let loaded = try store.load()
        XCTAssertEqual(loaded.interfaceStyle, .system)
        XCTAssertEqual(loaded.pages[0].snapshot?.name, "GitHub")
        XCTAssertTrue(loaded.didSetLaunchAtLogin)
    }

    private func makeStore() throws -> PageStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return PageStore(directory: dir)
    }

    private func text(_ url: URL) throws -> String {
        try XCTUnwrap(String(data: try Data(contentsOf: url), encoding: .utf8))
    }
}
