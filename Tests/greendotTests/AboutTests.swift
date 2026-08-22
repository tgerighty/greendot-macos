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

    func testAboutOptionsUseGitHashAsBuildVersion() {
        let options = AboutPanel.options(gitHash: "deadbeefcafebabe")
        XCTAssertEqual(options[.version] as? String, "deadbeefcafebabe")
    }
}
