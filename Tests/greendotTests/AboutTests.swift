import AppKit
import XCTest
@testable import greendot

final class AboutTests: XCTestCase {
    func testGitHashReadsGitCommitHashFromInfoDictionary() {
        XCTAssertEqual(
            BuildInfo.gitHash(from: ["GitCommitHash": "abc123def456"]),
            "abc123def456"
        )
    }

    func testGitHashIsUnknownWhenMissingOrEmpty() {
        XCTAssertEqual(BuildInfo.gitHash(from: [:]), "unknown")
        XCTAssertEqual(BuildInfo.gitHash(from: nil), "unknown")
        XCTAssertEqual(BuildInfo.gitHash(from: ["GitCommitHash": ""]), "unknown")
    }

    func testVersionReadsShortVersionStringFromInfoDictionary() {
        XCTAssertEqual(
            BuildInfo.version(from: ["CFBundleShortVersionString": "24"]),
            "24"
        )
    }

    func testVersionIsUnknownWhenMissingOrEmpty() {
        XCTAssertEqual(BuildInfo.version(from: [:]), "unknown")
        XCTAssertEqual(BuildInfo.version(from: nil), "unknown")
        XCTAssertEqual(BuildInfo.version(from: ["CFBundleShortVersionString": ""]), "unknown")
    }

    func testAboutOptionsUseMergeCountAndShortHash() {
        let options = AboutPanel.options(version: "24", gitHash: "adb7e2c")
        XCTAssertEqual(options[.applicationVersion] as? String, "24")
        XCTAssertEqual(options[.version] as? String, "adb7e2c")
    }

    func testShortHashUsesFirstSevenCharacters() {
        XCTAssertEqual(
            BuildInfo.shortHash(from: ["GitCommitHash": "95596754a2720ff00eaf2078527858d67d958a2e"]),
            "9559675"
        )
        XCTAssertEqual(BuildInfo.shortHash(from: ["GitCommitHash": "abc1234"]), "abc1234")
        XCTAssertEqual(BuildInfo.shortHash(from: nil), "unknown")
    }
}
