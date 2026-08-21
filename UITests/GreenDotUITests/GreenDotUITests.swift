import AppKit
import XCTest

/// End-to-end tests. Menu and panel actions are sent through distributed
/// notifications so XCTest never moves the pointer (off-screen extra frames
/// map to the bottom-left hot corner and lock the Mac).
final class GreenDotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var configDirectory: URL!
    private var fixtureRoot: URL!
    private var urlLog: URL!
    private var menuDumpFile: URL!
    private var idDumpFile: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("greendot-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        fixtureRoot = configDirectory.appendingPathComponent("www")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        urlLog = configDirectory.appendingPathComponent("opened-urls.log")
        menuDumpFile = configDirectory.appendingPathComponent("menu-dump.txt")
        idDumpFile = configDirectory.appendingPathComponent("id-dump.txt")
        try writeSummary(host: "www.githubstatus.com", json: Self.githubJSON)
        try writeSummary(host: "status.box.com", json: Self.boxJSON)
        try chmodTree(configDirectory)

        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("greendot.app")
        app = XCUIApplication(url: appURL)
        app.launchEnvironment["GREENDOT_CONFIG_DIR"] = configDirectory.path
        app.launchEnvironment["GREENDOT_FIXTURE_DIR"] = fixtureRoot.path
        app.launchEnvironment["GREENDOT_SKIP_LOGIN_ITEM"] = "1"
        app.launchEnvironment["GREENDOT_SKIP_SEED"] = "1"
        app.launchEnvironment["GREENDOT_POLL_SECONDS"] = "3600"
        app.launchEnvironment["GREENDOT_UI_TEST"] = "1"
        app.launchEnvironment["GREENDOT_OPEN_URL_LOG"] = urlLog.path
        app.launchEnvironment["GREENDOT_MENU_DUMP"] = menuDumpFile.path
        app.launchEnvironment["GREENDOT_ID_DUMP"] = idDumpFile.path
        app.launch()
        XCTAssertTrue(statusItem.waitForExistence(timeout: 8))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: configDirectory)
    }

    private var statusItem: XCUIElement { app.statusItems.firstMatch }

    func testStatusItemAppearsAndHasNoDockWindows() throws {
        XCTAssertEqual(app.windows.count, 0)
    }

    func testMenuHasAddRefreshLaunchAtLoginAndQuit() throws {
        let dump = menuDump()
        XCTAssertTrue(dump.contains("Add Status Page…"), dump)
        XCTAssertTrue(dump.contains("Refresh"), dump)
        XCTAssertTrue(dump.contains("Launch at Login"), dump)
        XCTAssertTrue(dump.contains("Quit greendot"), dump)
        XCTAssertTrue(dump.contains("No status pages"), dump)
    }

    func testAddPageShowsComponentsInSubmenu() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        let dump = menuDump()
        XCTAssertTrue(dump.contains("GitHub"), dump)
        XCTAssertTrue(dump.contains("API    Operational"), dump)
        XCTAssertTrue(dump.contains("Git Operations    Operational"), dump)
        XCTAssertTrue(dump.contains("Webhooks    Operational"), dump)
        XCTAssertTrue(dump.contains("Notifications [on]"), dump)
        XCTAssertTrue(dump.contains("Edit…"), dump)
        XCTAssertTrue(dump.contains("Remove"), dump)
        XCTAssertTrue(dump.contains("Open Status Page"), dump)
    }

    func testPageRowClickOpensStatusURL() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("GitHub")
        assertOpened("https://www.githubstatus.com")
    }

    func testComponentRowClickOpensStatusURL() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("API    Operational")
        assertOpened("https://www.githubstatus.com")
    }

    func testGroupRowClickOpensStatusURL() throws {
        try addPage(url: "https://status.box.com", expectedName: "Box")
        clickMenu("Box Web Application")
        assertOpened("https://status.box.com")
    }

    func testOpenStatusPageOpensURL() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("GitHub/Open Status Page")
        assertOpened("https://www.githubstatus.com")
    }

    func testIncidentRowOpensURL() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("API blip")
        assertOpened("https://www.githubstatus.com")
    }

    func testPasteIntoAddFieldCreatesPage() throws {
        clickMenu("Add Status Page…")
        XCTAssertTrue(app.windows["Add Status Page"].waitForExistence(timeout: 5))
        post("com.tgerighty.greendot.focusField", object: "url-field")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://www.githubstatus.com", forType: .string)
        app.typeKey("v", modifierFlags: .command)
        post("com.tgerighty.greendot.clickIdentifier", object: "save-button")
        try waitForSaved(name: "GitHub")
        XCTAssertTrue(menuDump().contains("GitHub"))
    }

    func testEditRenamesAndChangesURL() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("GitHub/Edit…")
        XCTAssertTrue(app.windows["Edit Status Page"].waitForExistence(timeout: 5))
        post("com.tgerighty.greendot.setField", object: "name-field\tGH")
        post("com.tgerighty.greendot.setField", object: "url-field\thttps://status.box.com")
        post("com.tgerighty.greendot.clickIdentifier", object: "save-button")
        try waitForSaved(name: "GH")
        let dump = menuDump()
        XCTAssertTrue(dump.contains("GH"), dump)
        XCTAssertTrue(dump.contains("Box Web Application"), dump)
    }

    func testNotificationToggle() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        XCTAssertTrue(menuDump().contains("Notifications [on]"))
        clickMenu("GitHub/Notifications")
        XCTAssertTrue(menuDump().contains("Notifications [off]"))
    }

    func testRemoveDeletesThePage() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("GitHub/Remove")
        let dump = menuDump()
        XCTAssertTrue(dump.contains("No status pages"), dump)
        XCTAssertFalse(dump.contains("GitHub"))
    }

    func testCancelAddDoesNotCreateAPage() throws {
        clickMenu("Add Status Page…")
        XCTAssertTrue(app.windows["Add Status Page"].waitForExistence(timeout: 5))
        post("com.tgerighty.greendot.clickIdentifier", object: "cancel-button")
        XCTAssertTrue(menuDump().contains("No status pages"))
    }

    func testRefreshStaysAlive() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        clickMenu("Refresh")
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertTrue(menuDump().contains("GitHub"))
    }

    func testEditTogglesEveryComponentFiveTimes() throws {
        try addPage(url: "https://status.box.com", expectedName: "Box")
        clickMenu("Box/Edit…")
        XCTAssertTrue(app.windows["Edit Status Page"].waitForExistence(timeout: 5))
        let ids = identifierDump().filter { $0.hasPrefix("component-") && $0 != "component-list" }
        XCTAssertGreaterThanOrEqual(ids.count, 5, "\(ids)")
        for _ in 1...5 {
            for identifier in ids {
                post("com.tgerighty.greendot.clickIdentifier", object: identifier)
            }
        }
        XCTAssertTrue(app.windows["Edit Status Page"].exists)
        XCTAssertTrue(statusItem.exists)
        post("com.tgerighty.greendot.clickIdentifier", object: "cancel-button")
    }

    func testSwitchingEditBetweenPagesFiveTimesDoesNotCrash() throws {
        try addPage(url: "https://www.githubstatus.com", expectedName: "GitHub")
        try addPage(url: "https://status.box.com", expectedName: "Box")
        for _ in 1...5 {
            clickMenu("GitHub/Edit…")
            XCTAssertTrue(app.windows["Edit Status Page"].waitForExistence(timeout: 5))
            clickMenu("Box/Edit…")
            XCTAssertTrue(app.windows["Edit Status Page"].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(statusItem.exists)
        XCTAssertTrue(app.windows["Edit Status Page"].exists)
    }

    func testQuit() throws {
        clickMenu("Quit greendot")
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    private func addPage(url: String, expectedName: String) throws {
        clickMenu("Add Status Page…")
        XCTAssertTrue(app.windows["Add Status Page"].waitForExistence(timeout: 5))
        post("com.tgerighty.greendot.setField", object: "url-field\t\(url)")
        post("com.tgerighty.greendot.clickIdentifier", object: "save-button")
        try waitForSaved(name: expectedName)
    }

    private func clickMenu(_ path: String) {
        post("com.tgerighty.greendot.clickMenu", object: path)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func post(_ name: String, object: String? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(name),
            object: object,
            userInfo: nil,
            deliverImmediately: true
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func menuDump() -> String {
        waitForFile(menuDumpFile) {
            post("com.tgerighty.greendot.dumpMenu")
        }
    }

    private func identifierDump() -> [String] {
        waitForFile(idDumpFile) {
            post("com.tgerighty.greendot.dumpIdentifiers")
        }
        .split(whereSeparator: \.isNewline)
        .map(String.init)
    }

    private func waitForFile(_ url: URL, trigger: () -> Void) -> String {
        try? FileManager.default.removeItem(at: url)
        trigger()
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let body = try? String(contentsOf: url, encoding: .utf8), !body.isEmpty {
                return body
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("missing dump \(url.lastPathComponent)")
        return ""
    }

    private func waitForSaved(name: String) throws {
        let config = configDirectory.appendingPathComponent("config.json")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let data = try? Data(contentsOf: config),
               let body = String(data: data, encoding: .utf8),
               body.contains(name) {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("page was not saved to \(config.path)")
    }

    private func assertOpened(_ url: String) {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if openedURLs().contains(url) { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("expected \(url) in \(openedURLs())")
    }

    private func openedURLs() -> [String] {
        let body = (try? String(contentsOf: urlLog, encoding: .utf8)) ?? ""
        return body.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func writeSummary(host: String, json: Data) throws {
        let dir = fixtureRoot.appendingPathComponent("\(host)/api/v2")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("summary.json"))
    }

    private func chmodTree(_ root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: root.path)
        if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                try fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: url.path)
            }
        }
    }

    private static let githubJSON = Data("""
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none", "description": "All Systems Operational"},
          "components": [
            {"name": "API", "status": "operational", "group": false},
            {"name": "Git Operations", "status": "operational", "group": false},
            {"name": "Webhooks", "status": "operational", "group": false}
          ],
          "incidents": [{"name": "API blip", "shortlink": "https://www.githubstatus.com"}]
        }
        """.utf8)

    private static let boxJSON = Data("""
        {
          "page": {"name": "Box", "url": "https://status.box.com"},
          "status": {"indicator": "none", "description": "All Systems Operational"},
          "components": [
            {"id": "g1", "name": "Box Web Application", "status": "operational", "group": true},
            {"id": "c1", "name": "Login/SSO", "status": "operational", "group": false, "group_id": "g1"},
            {"id": "c2", "name": "Search", "status": "operational", "group": false, "group_id": "g1"},
            {"id": "c3", "name": "Files", "status": "operational", "group": false, "group_id": "g1"},
            {"id": "c4", "name": "Content API", "status": "operational", "group": false}
          ],
          "incidents": []
        }
        """.utf8)
}
