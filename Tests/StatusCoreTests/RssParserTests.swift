import XCTest
@testable import StatusCore

final class RssParserTests: XCTestCase {
    func testRSSItemWithServiceDegradationIsYellow() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
          <channel>
            <title>Microsoft Admin Center Status</title>
            <link>https://status.cloud.microsoft/</link>
            <item>
              <guid isPermaLink="false">7118ff1f-8d1b-47af-a498-38829141e714</guid>
              <link>https://status.cloud.microsoft/</link>
              <title>Microsoft Admin Center</title>
              <status>ServiceDegradation</status>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.cloud.microsoft/api/feed/mac")!
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Microsoft Admin Center Status")
        XCTAssertEqual(snap.url, URL(string: "https://status.cloud.microsoft/")!)
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.incidents, [])
        XCTAssertFalse(snap.isUnreachable)
        XCTAssertEqual(snap.components.count, 1)
        XCTAssertEqual(snap.components[0].id, "7118ff1f-8d1b-47af-a498-38829141e714")
        XCTAssertEqual(snap.components[0].name, "Microsoft Admin Center")
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
        XCTAssertFalse(snap.components[0].isGroup)
        XCTAssertTrue(snap.components[0].children.isEmpty)
    }

    func testMinorStatusDisplaysAsDegraded() throws {
        let data = Data("""
        <rss version="2.0"><channel><title>Example</title>
        <item><title>Blip</title><status>minor</status></item></channel></rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
    }

    func testAtomRelativeLinkResolvesAgainstSource() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <link href="/status"/>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.url, URL(string: "https://status.example.com/status")!)
    }

    func testAzureRSSItemWithoutStatusIsYellow() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Azure Status</title>
            <item>
              <title>West Europe Storage</title>
              <description>Investigating connectivity</description>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://rssfeed.azure.status.microsoft/en-us/status/feed/")!
        )
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
    }

    func testRSSItemWithoutStatusIsOperational() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <link>https://status.example.com</link>
            <item>
              <title>Scheduled note</title>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].id, "Scheduled note")
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testEmptyRSSChannelIsGreenWithNoComponents() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Azure Status</title>
            <link>https://azure.status.microsoft/en-us/status/</link>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://rssfeed.azure.status.microsoft/en-us/status/feed/")!
        )
        XCTAssertEqual(snap.name, "Azure Status")
        XCTAssertEqual(snap.overall, .green)
        XCTAssertTrue(snap.components.isEmpty)
        XCTAssertTrue(snap.incidents.isEmpty)
    }

    func testAtomEntryWithoutStatusIsOperational() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <link href="https://status.example.com/"/>
          <entry>
            <title>All clear</title>
            <id>urn:uuid:abc</id>
            <link href="https://status.example.com/1"/>
          </entry>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Example")
        XCTAssertEqual(snap.url, URL(string: "https://status.example.com/")!)
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].id, "urn:uuid:abc")
        XCTAssertEqual(snap.components[0].name, "All clear")
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testRssParserRejectsJSON() {
        let data = Data("""
        {"page": {"name": "GitHub"}, "status": {"indicator": "none"}}
        """.utf8)
        XCTAssertThrowsError(
            try RssParser.parse(data: data, sourceURL: URL(string: "https://www.githubstatus.com")!)
        ) { error in
            XCTAssertEqual(error as? ParserError, .notThisProvider)
        }
    }

    func testUnknownStatusIsYellowWithRawText() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>Weird</title>
              <status>Investigating</status>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Investigating")
    }

    func testAvailableStatusIsGreen() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Power Platform Admin Center Status</title>
            <link>https://status.cloud.microsoft/</link>
            <item>
              <guid>9b80edb9-2bb5-47fa-a1d3-8b53dbe65be1</guid>
              <title>Power Platform Admin Center</title>
              <status>Available</status>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.cloud.microsoft/api/feed/ppac")!
        )
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testServiceInterruptionIsRed() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>Down</title>
              <status>ServiceInterruption</status>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
    }

    func testMissingTitleFallsBackToHost() throws {
        let data = Data("""
        <rss version="2.0"><channel></channel></rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://feeds.example.com/status")!
        )
        XCTAssertEqual(snap.name, "feeds.example.com")
        XCTAssertEqual(snap.url, URL(string: "https://feeds.example.com/status")!)
    }
}
