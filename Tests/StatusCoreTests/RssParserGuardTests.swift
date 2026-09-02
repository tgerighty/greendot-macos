import XCTest
@testable import StatusCore
import TestSupport

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

    func testProbeReadsUTF16RSSFeed() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-16"?>
        <rss version="2.0"><channel><title>Secret Feed</title>
        <item><guid>item-1</guid><title>API</title><status>Available</status></item>
        </channel></rss>
        """
        let data = try XCTUnwrap(xml.data(using: .utf16))
        var client = MapHTTPClient()
        let page = URL(string: "https://status.example.com/feed.xml")!
        client.byURL[page.absoluteString] = (data, 200)
        let snap = try await ProviderProbe.probe(pageURL: page, client: client)
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Secret Feed")
    }
}
