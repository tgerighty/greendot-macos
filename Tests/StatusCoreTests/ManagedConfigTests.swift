import Foundation
import XCTest
@testable import StatusCore
import TestSupport

final class ManagedConfigTests: XCTestCase {
    func testDisabledOptionalManagedPageCanBeEnabledAndPersists() throws {
        let root = try makeRoot()
        let id = UUID()
        let managedURL = root.appendingPathComponent("managed.json")
        let json = #"""
        {"version":2,"pages":[
          {"id":"\#(id)","url":"https://optional.example","name":"Optional","required":false}
        ]}
        """#
        try Data(json.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        let monitor = Monitor(store: store, client: MapHTTPClient())
        try monitor.load()
        try monitor.remove(id: id)
        XCTAssertTrue(monitor.pages.isEmpty)
        XCTAssertEqual(monitor.disabledManagedPages.map(\.id), [id])
        try monitor.enableManagedPage(id: id)
        XCTAssertEqual(monitor.pages.map(\.id), [id])
        XCTAssertTrue(monitor.disabledManagedPages.isEmpty)
        XCTAssertEqual(try store.load().pages.map(\.id), [id])
        let savedData = try Data(contentsOf: store.configURL)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        XCTAssertNil(saved["disabledManagedPageIDs"])
    }

    func testManagedPagesMergeWithLocalExtrasAndOptionalDisablePersistsLocally() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let userDir = root.appendingPathComponent("user")
        let requiredID = UUID()
        let optionalID = UUID()
        let extraID = UUID()
        let managed = #"""
        {"version":2,"pollSeconds":60,"pages":[
          {"id":"\#(requiredID)","url":"https://required.example","name":"Required","required":true,"token":"secret"},
          {"id":"\#(optionalID)","url":"https://optional.example","name":"Optional","required":false}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: userDir, managedConfigURL: managedURL)
        var loaded = try store.load()
        XCTAssertEqual(loaded.pages.map(\.id), [requiredID, optionalID])
        loaded.pages.removeAll { $0.id == optionalID }
        loaded.pages.append(page(id: extraID, url: "https://extra.example", name: "Local"))
        try store.save(loaded)
        let saved = try store.load()
        XCTAssertEqual(saved.pages.map(\.id), [requiredID, extraID])
        XCTAssertEqual(saved.pages.first?.token, "secret")
        let localData = try Data(contentsOf: store.configURL)
        let localJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: localData) as? [String: Any])
        let localPages = try XCTUnwrap(localJSON["pages"] as? [[String: Any]])
        XCTAssertEqual(localPages.compactMap { $0["id"] as? String }, [extraID.uuidString])
        XCTAssertEqual(localJSON["disabledManagedPageIDs"] as? [String], [optionalID.uuidString])
    }

    func testRequiredManagedPageCannotBeRemoved() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let requiredID = UUID()
        let managed = #"""
        {"version":2,"pages":[
          {"id":"\#(requiredID)","url":"https://required.example","name":"Required","required":true}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        var loaded = try store.load()
        loaded.pages.removeAll()
        XCTAssertThrowsError(try store.save(loaded))
    }

    func testSaveBeforeLoadDoesNotPersistManagedPagesLocally() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let managedID = UUID()
        let managed = #"""
        {"version":2,"pages":[
          {"id":"\#(managedID)","url":"https://required.example","name":"Required","required":true,"token":"secret"}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        XCTAssertThrowsError(try store.save(AppConfig())) { error in
            XCTAssertEqual(error as? StoreError, .requiredManagedPage)
        }
        try store.save(AppConfig(pages: [
            page(id: managedID, url: "https://required.example", name: "Required", token: "secret")
        ]))

        let localData = try Data(contentsOf: store.configURL)
        let localJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: localData) as? [String: Any])
        let localPages = try XCTUnwrap(localJSON["pages"] as? [[String: Any]])
        XCTAssertTrue(localPages.isEmpty)
        XCTAssertEqual(try store.load().pages.map(\.id), [managedID])
    }

    func testSaveAllowsManagedPagesAddedSinceLastLoad() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let existingID = UUID()
        let newID = UUID()
        let newRequiredID = UUID()
        let initial = #"""
        {"version":2,"pages":[
          {"id":"\#(existingID)","url":"https://existing.example","name":"Existing","required":false}
        ]}
        """#
        try Data(initial.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        let loaded = try store.load()
        let updated = #"""
        {"version":2,"pages":[
          {"id":"\#(existingID)","url":"https://existing.example","name":"Existing","required":false},
          {"id":"\#(newID)","url":"https://new.example","name":"New","required":false},
          {"id":"\#(newRequiredID)","url":"https://required.example","name":"Required","required":true}
        ]}
        """#
        try Data(updated.utf8).write(to: managedURL)
        try store.save(loaded)
        try store.save(loaded)

        XCTAssertEqual(try store.load().pages.map(\.id), [existingID, newID, newRequiredID])
    }

    func testRemovedManagedPageIsNotSavedAsALocalPage() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let managedID = UUID()
        let managed = #"""
        {"version":2,"pages":[
          {"id":"\#(managedID)","url":"https://managed.example","name":"Managed","token":"secret"}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        let loaded = try store.load()
        try FileManager.default.removeItem(at: managedURL)
        try store.save(loaded)

        let localData = try Data(contentsOf: store.configURL)
        let localJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: localData) as? [String: Any])
        let localPages = try XCTUnwrap(localJSON["pages"] as? [[String: Any]])
        XCTAssertTrue(localPages.isEmpty)
        let savedText = try XCTUnwrap(String(bytes: localData, encoding: .utf8))
        XCTAssertFalse(savedText.contains("secret"))
    }

    func testCorruptManagedConfigDoesNotBlockLocalSaveAfterLoad() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let managedID = UUID()
        let managed = #"""
        {"version":2,"pages":[
          {"id":"\#(managedID)","url":"https://managed.example","name":"Managed","token":"secret"}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)
        var loaded = try store.load()
        let localID = UUID()
        loaded.pages.append(page(id: localID, url: "https://local.example", name: "Local"))
        try Data("{".utf8).write(to: managedURL)
        try store.save(loaded)

        let localData = try Data(contentsOf: store.configURL)
        let localJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: localData) as? [String: Any])
        let localPages = try XCTUnwrap(localJSON["pages"] as? [[String: Any]])
        XCTAssertEqual(localPages.compactMap { $0["id"] as? String }, [localID.uuidString])
    }

    func testDuplicateManagedPageIDsAreRejected() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let id = UUID()
        let managed = #"""
        {"version":2,"pages":[
          {"id":"\#(id)","url":"https://first.example","name":"First"},
          {"id":"\#(id)","url":"https://second.example","name":"Second"}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)

        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? StoreError, .corrupt)
        }
    }

    func testManagedPagesWithoutIDsGetStableUniqueIDsAcrossLoads() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let managed = #"""
        {"version":2,"pages":[
          {"url":"https://same.example","name":"Same","required":false},
          {"url":"https://same.example","name":"Same","required":false}
        ]}
        """#
        try Data(managed.utf8).write(to: managedURL)
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)

        var config = try store.load()
        let originalIDs = config.pages.map(\.id)
        let disabledID = try XCTUnwrap(originalIDs.last)
        config.pages.removeLast()
        try store.save(config)
        let secondLoad = try store.load()
        let thirdLoad = try store.load()

        XCTAssertEqual(Set(originalIDs).count, 2)
        XCTAssertEqual(secondLoad.pages.map(\.id), [originalIDs[0]])
        XCTAssertEqual(secondLoad.disabledManagedPages.map(\.id), [disabledID])
        XCTAssertEqual(secondLoad.disabledManagedPages.map(\.id), thirdLoad.disabledManagedPages.map(\.id))
    }

    func testManagedConfigWithoutPagesLoadsAsEmpty() throws {
        let root = try makeRoot()
        let managedURL = root.appendingPathComponent("managed.json")
        let store = PageStore(directory: root.appendingPathComponent("user"), managedConfigURL: managedURL)

        for managed in ["{}", #"{"pages":null}"#] {
            try Data(managed.utf8).write(to: managedURL)

            XCTAssertTrue(try store.load().pages.isEmpty)
        }
    }

    func testLocalPagesDoNotRetainManagedPolicyFlags() throws {
        for hasManagedConfig in [false, true] {
            let root = try makeRoot()
            let userDir = root.appendingPathComponent("user")
            let managedURL = root.appendingPathComponent("managed.json")
            let localID = UUID()
            try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
            let local = #"""
            {"version":2,"pages":[
              {"id":"\#(localID)","url":"https://local.example","name":"Local","required":true}
            ]}
            """#
            try Data(local.utf8).write(to: userDir.appendingPathComponent("config.json"))
            if hasManagedConfig {
                try Data(#"{"version":2,"pages":[]}"#.utf8).write(to: managedURL)
            }
            let store = PageStore(directory: userDir, managedConfigURL: managedURL)

            XCTAssertNil(try store.load().pages.first?.required)
        }
    }

    private func page(id: UUID, url: String, name: String, token: String? = nil) -> WatchedPage {
        WatchedPage(id: id, url: URL(string: url)!, name: name, token: token)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
