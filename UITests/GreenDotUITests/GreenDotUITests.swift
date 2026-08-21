import XCTest

/// End-to-end tests against the real menu bar on this Mac.
final class GreenDotUITests: XCTestCase {
    private var app: XCUIApplication!
    private var configDirectory: URL!
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        configDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("greendot-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: configDirectory.path)
        fixtureRoot = configDirectory.appendingPathComponent("www")
        try FileManager.default.createDirectory(
            at: fixtureRoot.appendingPathComponent("api/v2"),
            withIntermediateDirectories: true
        )
        try Self.statusJSON(name: "GitHub").write(
            to: fixtureRoot.appendingPathComponent("api/v2/summary.json")
        )
        let paths = [
            configDirectory.path,
            fixtureRoot.path,
            fixtureRoot.appendingPathComponent("api").path,
            fixtureRoot.appendingPathComponent("api/v2").path
        ]
        for path in paths {
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: path)
        }

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
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        try? FileManager.default.removeItem(at: configDirectory)
    }

    private var statusItem: XCUIElement { app.statusItems.firstMatch }

    private func openMenu() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 8))
        if statusItem.isHittable {
            statusItem.click()
        } else {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.tgerighty.greendot.showMenu"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        XCTAssertTrue(app.menuItems["Add Status Page…"].waitForExistence(timeout: 5))
    }

    private func clickMenu(_ title: String) {
        let item = app.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "missing menu item \(title)")
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    func testStatusItemAppearsAndHasNoDockWindows() throws {
        XCTAssertTrue(statusItem.waitForExistence(timeout: 8))
        XCTAssertEqual(app.windows.count, 0)
    }

    func testMenuHasAddRefreshLaunchAtLoginAndQuit() throws {
        try openMenu()
        XCTAssertTrue(app.menuItems["Add Status Page…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Refresh"].exists)
        XCTAssertTrue(app.menuItems["Launch at Login"].exists)
        XCTAssertTrue(app.menuItems["Quit greendot"].exists)
        XCTAssertTrue(app.menuItems["No status pages"].exists)
    }

    func testAddPageShowsComponentsInSubmenu() throws {
        try addFixturePage()
        try openMenu()
        XCTAssertTrue(app.menuItems["GitHub"].waitForExistence(timeout: 5))
        clickMenu("GitHub")
        XCTAssertTrue(app.menuItems["API    Operational"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Notifications"].exists)
        XCTAssertTrue(app.menuItems["Edit…"].exists)
        XCTAssertTrue(app.menuItems["Remove"].exists)
        XCTAssertTrue(app.menuItems["Open Status Page"].exists)
    }

    func testEditRenamesThePage() throws {
        try addFixturePage()
        try openMenu()
        XCTAssertTrue(app.menuItems["GitHub"].waitForExistence(timeout: 5))
        clickMenu("GitHub")
        clickMenu("Edit…")
        let panel = app.windows["Edit Status Page"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let name = panel.textFields["name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("GH")
        panel.buttons["Save"].click()
        try openMenu()
        XCTAssertTrue(app.menuItems["GH"].waitForExistence(timeout: 5))
    }

    func testRemoveDeletesThePage() throws {
        try addFixturePage()
        try openMenu()
        clickMenu("GitHub")
        clickMenu("Remove")
        try openMenu()
        XCTAssertTrue(app.menuItems["No status pages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["GitHub"].exists)
    }

    func testCancelAddDoesNotCreateAPage() throws {
        try openMenu()
        clickMenu("Add Status Page…")
        let panel = app.windows["Add Status Page"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        panel.buttons["Cancel"].click()
        try openMenu()
        XCTAssertTrue(app.menuItems["No status pages"].waitForExistence(timeout: 3))
    }

    private func addFixturePage() throws {
        try openMenu()
        clickMenu("Add Status Page…")
        let panel = app.windows["Add Status Page"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let url = panel.textFields["url-field"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.click()
        url.typeText("https://www.githubstatus.com")
        panel.buttons["Add"].click()
        let config = configDirectory.appendingPathComponent("config.json")
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let data = try? Data(contentsOf: config),
               let body = String(data: data, encoding: .utf8),
               body.contains("GitHub") {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("page was not saved to \(config.path)")
    }

    private static func statusJSON(name: String) -> Data {
        Data("""
        {
          "page": {"name": "\(name)", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none", "description": "All Systems Operational"},
          "components": [{"name": "API", "status": "operational", "group": false}],
          "incidents": []
        }
        """.utf8)
    }
}
