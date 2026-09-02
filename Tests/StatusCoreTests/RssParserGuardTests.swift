import XCTest
@testable import StatusCore

final class RssParserGuardTests: XCTestCase {
    func testNonAtomFeedRootIsRejected() {
        XCTAssertThrowsError(
            try RssParser.parse(
                data: Data("<feed xmlns=\"https://example.com/custom\"/>".utf8),
                sourceURL: URL(string: "https://status.example.com/feed")!
            )
        ) { error in
            XCTAssertEqual(error as? ParserError, .notThisProvider)
        }
    }

    func testAzureMissingStatusDoesNotMatchContainingHost() throws {
        let data = Data("""
        <rss version="2.0"><channel><title>Azure Status</title>
        <item><title>West Europe Storage</title></item></channel></rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://azure.status.microsoft.example.com/feed")!
        )
        XCTAssertEqual(snap.components[0].severity, .green)
    }
}
