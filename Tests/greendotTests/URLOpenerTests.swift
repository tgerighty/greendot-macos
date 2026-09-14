import XCTest
@testable import greendot

final class URLOpenerTests: XCTestCase {
    func testLogPathRecordsURLAndSkipsWorkspace() {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("opened-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        var workspaceCalls: [URL] = []
        let url = URL(string: "https://www.githubstatus.com")!
        URLOpener.open(url, logPath: log.path, workspace: { workspaceCalls.append($0) })
        let body = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertEqual(body, "https://www.githubstatus.com\n")
        XCTAssertTrue(workspaceCalls.isEmpty)
    }

    func testMissingLogPathUsesWorkspace() {
        var workspaceCalls: [URL] = []
        let url = URL(string: "https://status.box.com")!
        URLOpener.open(url, logPath: nil, workspace: { workspaceCalls.append($0) })
        XCTAssertEqual(workspaceCalls, [url])
    }

    func testAppendsEachOpenOnItsOwnLine() {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("opened-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        URLOpener.open(URL(string: "https://a.example")!, logPath: log.path, workspace: { _ in })
        URLOpener.open(URL(string: "https://b.example")!, logPath: log.path, workspace: { _ in })
        let body = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertEqual(body, "https://a.example\nhttps://b.example\n")
    }

    func testRejectsNonHTTPSchemes() {
        var workspaceCalls: [URL] = []
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("opened-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        URLOpener.open(URL(string: "file:///etc/passwd")!, logPath: log.path, workspace: { workspaceCalls.append($0) })
        URLOpener.open(URL(string: "javascript:alert(1)")!, logPath: nil, workspace: { workspaceCalls.append($0) })
        XCTAssertTrue(workspaceCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.path))
    }

    func testAllowsHTTP() {
        var workspaceCalls: [URL] = []
        let url = URL(string: "http://status.example")!
        URLOpener.open(url, logPath: nil, workspace: { workspaceCalls.append($0) })
        XCTAssertEqual(workspaceCalls, [url])
    }

    func testStripsUserinfoBeforeOpenAndLog() {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("opened-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        var workspaceCalls: [URL] = []
        let url = URL(string: "https://user:secret@icinga.example:5665/v1")!
        URLOpener.open(url, logPath: nil, workspace: { workspaceCalls.append($0) })
        URLOpener.open(url, logPath: log.path, workspace: { workspaceCalls.append($0) })
        XCTAssertEqual(workspaceCalls, [URL(string: "https://icinga.example:5665/v1")!])
        let body = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        XCTAssertEqual(body, "https://icinga.example:5665/v1\n")
    }
}
