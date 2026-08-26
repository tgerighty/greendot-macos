import XCTest
@testable import greendot

@MainActor
final class CopyrightTests: XCTestCase {
    func testLicenseFileReservesAllRightsToTerryGerighty() throws {
        let body = try String(contentsOf: repoRoot.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(body.contains("Copyright © 2026 Terry Gerighty"), body)
        XCTAssertTrue(body.contains("All rights reserved"), body)
    }

    func testReadmeLicenseNamesTerryGerighty() throws {
        let body = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(body.contains("Copyright © 2026 Terry Gerighty"), body)
        XCTAssertTrue(body.contains("All rights reserved"), body)
    }

    func testInfoPlistHumanReadableCopyright() throws {
        let plistURL = repoRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(
            dict["NSHumanReadableCopyright"] as? String,
            "Copyright © 2026 Terry Gerighty. All rights reserved."
        )
    }

    func testAppMenuHasAboutGreendotAsFirstItem() {
        let appMenu = AppEditMenu.makeMainMenu().items.first?.submenu
        XCTAssertEqual(appMenu?.items.first?.title, "About greendot")
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
