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

    func testNamespacedChannelTitleDoesNotReplaceRSSTitle() throws {
        let data = Data("""
        <rss version="2.0"><channel>
          <media:title xmlns:media="http://search.yahoo.com/mrss/">Media title</media:title>
          <title>Real Channel</title>
          <item><guid>g1</guid><title>API</title><status>Available</status></item>
        </channel></rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.name, "Real Channel")
    }

    func testNamespacedRssRootIsRejected() {
        let data = Data("""
        <custom:rss xmlns:custom="urn:example">
          <custom:channel>
            <custom:title>Custom API</custom:title>
          </custom:channel>
        </custom:rss>
        """.utf8)
        XCTAssertThrowsError(
            try RssParser.parse(
                data: data,
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

    func testLooksLikeFeedSurvivesTruncatedUTF8Prefix() {
        var data = Data("<rss version=\"2.0\"><channel></channel></rss>".utf8)
        data.append(contentsOf: [UInt8](repeating: 0x20, count: 1000))
        data.append(0xE2)
        XCTAssertTrue(ProviderProbe.looksLikeFeed(Data(data.prefix(1024))))
    }

    func testLooksLikeFeedRecognizesPrefixedAtomRoot() {
        let data = Data("<atom:feed xmlns:atom=\"http://www.w3.org/2005/Atom\"></atom:feed>".utf8)
        XCTAssertTrue(ProviderProbe.looksLikeFeed(data))
    }

    func testAtomHubLinkIsNotUsedAsPageURL() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <link rel="hub" href="https://pubsubhubbub.example/hub"/>
        </feed>
        """.utf8)
        let source = URL(string: "https://status.example.com/atom.xml")!
        let snap = try RssParser.parse(data: data, sourceURL: source)
        XCTAssertEqual(snap.url, source)
    }

    func testAtomLinkLevelXMLBaseWinsOverFeedBase() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://status.example.com/app/">
          <title>Example</title>
          <link rel="alternate" xml:base="https://status.example.com/portal/" href="status"/>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.url, URL(string: "https://status.example.com/portal/status")!)
    }

    func testAtomRelativeLinkResolvesAgainstXMLBase() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://status.example.com/app/">
          <title>Example</title>
          <link rel="alternate" href="status"/>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.url, URL(string: "https://status.example.com/app/status")!)
    }

    func testAtomAlternateLinkBeatsEarlierSelfLink() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <link rel="self" href="https://status.example.com/atom.xml"/>
          <link rel="alternate" href="https://status.example.com/status"/>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.url, URL(string: "https://status.example.com/status")!)
    }
}
