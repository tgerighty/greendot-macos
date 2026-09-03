import XCTest
@testable import StatusCore

final class RssParserCategoryTests: XCTestCase {
    func testRSSCategoryOutageWithoutStatusIsRed() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>SpaceXAI System Status</title>
            <item>
              <guid isPermaLink="false">INCc33a8af</guid>
              <title>[Grok (iOS)] Models outage</title>
              <category>outage</category>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.x.ai/feed.xml")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].id, "INCc33a8af")
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
    }

    func testUnrecognizedRSSCategoryWithoutStatusStaysOperational() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>Note</title>
              <category>West Europe</category>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testWorstKnownRSSCategoryWins() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>API</title>
              <category>active</category>
              <category>degraded</category>
              <category>outage</category>
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

    func testRSSDescriptionSeverityOutageWithoutStatusIsRed() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>SpaceXAI System Status</title>
            <item>
              <guid isPermaLink="false">INC3b127ff3</guid>
              <title>[Grok (Android)] Models outage</title>
              <description><![CDATA[
                <h3>Status: ACTIVE</h3>
                <p>Severity: outage</p>
              ]]></description>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.x.ai/feed.xml")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
    }

    func testAtomCategoryTermOutageWithoutStatusIsRed() throws {
        let data = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example</title>
          <entry>
            <title>[Grok (Web)] Models outage</title>
            <id>INC25664c15</id>
            <category term="outage"/>
          </entry>
        </feed>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/atom.xml")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components[0].severity, .red)
        XCTAssertEqual(snap.components[0].statusText, "Major outage")
    }

    func testRSSCategoryDisruptionWithoutStatusIsYellow() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>[API (us-east-1.api.x.ai)] grok-4.6 and grok-4.5 high error rate</title>
              <category>disruption</category>
              <category>active</category>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.x.ai/feed.xml")!
        )
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components[0].severity, .yellow)
        XCTAssertEqual(snap.components[0].statusText, "Degraded")
    }

    func testRSSDescriptionResolvedIsOperationalEvenIfSeveritySaysOutage() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>SpaceXAI System Status</title>
            <item>
              <title>[API (us-east-1.api.x.ai)] grok-4.6 and grok-4.5 high error rate</title>
              <description><![CDATA[
                <h3>Status: RESOLVED</h3>
                <p>Severity: outage</p>
              ]]></description>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.x.ai/feed.xml")!
        )
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testRSSStatusTagBeatsCategory() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>Example</title>
            <item>
              <title>API</title>
              <status>Available</status>
              <category>outage</category>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.example.com/feed")!
        )
        XCTAssertEqual(snap.overall, .green)
        XCTAssertEqual(snap.components[0].severity, .green)
        XCTAssertEqual(snap.components[0].statusText, "Operational")
    }

    func testXAIActiveOutageKeepsResolvedHistoryGreen() throws {
        let data = Data("""
        <rss version="2.0">
          <channel>
            <title>SpaceXAI System Status</title>
            <link>https://status.x.ai</link>
            <item>
              <title>[Grok (iOS)] Models outage</title>
              <guid isPermaLink="false">INCc33a8af</guid>
              <category>outage</category>
              <category>active</category>
              <description><![CDATA[
                <h3>Status: ACTIVE</h3>
                <p>Severity: outage</p>
              ]]></description>
            </item>
            <item>
              <title>[API (us-east-1.api.x.ai)] grok-4.6 and grok-4.5 high error rate</title>
              <guid isPermaLink="false">INC5a3245c3</guid>
              <category>available</category>
              <category>resolved</category>
              <description><![CDATA[
                <h3>Status: RESOLVED</h3>
                <p>Severity: available</p>
              ]]></description>
            </item>
          </channel>
        </rss>
        """.utf8)
        let snap = try RssParser.parse(
            data: data,
            sourceURL: URL(string: "https://status.x.ai/feed.xml")!
        )
        XCTAssertEqual(snap.overall, .red)
        XCTAssertEqual(snap.components.map(\.severity), [.red, .green])
        XCTAssertEqual(snap.components.map(\.statusText), ["Major outage", "Operational"])
    }
}
