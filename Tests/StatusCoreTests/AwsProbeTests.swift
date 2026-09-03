import XCTest
@testable import StatusCore
import TestSupport

final class AwsProbeTests: XCTestCase {
    private let eventsURL = "https://health.aws.amazon.com/public/currentevents"
    private let emptyJSON = Data("[]".utf8)
    private let awsRSS = """
    <rss version="2.0"><channel><title>Amazon S3 (N. Virginia)</title>
    <item><title>S3</title></item></channel></rss>
    """

    func testHealthLandingFetchesOnlyCurrentEvents() async throws {
        for page in [
            "https://health.aws.amazon.com/health/status",
            "https://health.aws.amazon.com",
            "https://health.aws.amazon.com/"
        ] {
            var inner = eventsClient()
            inner.byURL[page] = (Data("<html>spa</html>".utf8), 200)
            let recording = RecordingHTTPClient(inner)
            let url = URL(string: page)!
            let snap = try await ProviderProbe.probe(pageURL: url, client: recording)
            XCTAssertEqual(snap.provider, .aws, page)
            XCTAssertEqual(snap.name, "AWS", page)
            XCTAssertEqual(snap.url, ProviderProbe.normalizedBase(url), page)
            XCTAssertEqual(snap.overall, .green, page)
            XCTAssertTrue(snap.components.isEmpty, page)
            XCTAssertTrue(snap.incidents.isEmpty, page)
            XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL], page)
        }
    }

    func testStatusAWSEmptyPathDoesNotGetHTML() async throws {
        var inner = eventsClient()
        inner.byURL["https://status.aws.amazon.com/"] = (Data("<html>no</html>".utf8), 200)
        inner.byURL["https://status.aws.amazon.com"] = (Data("<html>no</html>".utf8), 200)
        inner.byURL["https://status.aws.amazon.com/api/v2/summary.json"] = (Data("{}".utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.aws.amazon.com/")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.name, "AWS")
        XCTAssertEqual(snap.url, URL(string: "https://status.aws.amazon.com")!)
        let requested = recording.requested.map(\.absoluteString)
        XCTAssertEqual(requested, [eventsURL])
        XCTAssertFalse(requested.contains { $0.contains("status.aws.amazon.com") })
    }

    func testCurrentEventsPasteStoresHealthStatusClickURL() async throws {
        let recording = RecordingHTTPClient(eventsClient())
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://health.aws.amazon.com/public/currentevents")!,
            client: recording
        )
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.name, "AWS")
        XCTAssertEqual(snap.url, URL(string: "https://health.aws.amazon.com/health/status")!)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL])
    }

    func testStatusAWSRSSIsNotHub() async throws {
        var inner = eventsClient()
        let page = URL(string: "https://status.aws.amazon.com/rss/s3-us-east-1.rss")!
        inner.byURL[page.absoluteString] = (Data(awsRSS.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(pageURL: page, client: recording)
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.name, "Amazon S3 (N. Virginia)")
        XCTAssertEqual(snap.overall, .yellow)
        XCTAssertEqual(snap.components.first?.severity, .yellow)
        XCTAssertFalse(recording.requested.map(\.absoluteString).contains(eventsURL))
    }

    func testContainingHostMissingStatusIsGreen() async throws {
        var client = MapHTTPClient()
        let page = URL(string: "https://status.aws.amazon.com.example.com/rss/s3.rss")!
        client.byURL[page.absoluteString] = (Data(awsRSS.utf8), 200)
        let snap = try await ProviderProbe.probe(pageURL: page, client: client)
        XCTAssertEqual(snap.provider, .rss)
        XCTAssertEqual(snap.components.first?.severity, .green)
    }

    func testPreferAWSOnLandingFetchesOnlyCurrentEvents() async throws {
        var inner = eventsClient()
        inner.byURL["https://health.aws.amazon.com/health/status/api/v2/summary.json"] = (
            Data("{}".utf8), 200
        )
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://health.aws.amazon.com/health/status")!,
            client: recording,
            prefer: .aws
        )
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL])
    }

    func testPreferAWSOnNonLandingDoesNotGetCurrentEvents() async throws {
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """
        var inner = MapHTTPClient()
        inner.byURL["https://www.githubstatus.com/api/v2/summary.json"] = (Data(json.utf8), 200)
        inner.byURL[eventsURL] = (emptyJSON, 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com")!,
            client: recording,
            prefer: .aws
        )
        XCTAssertEqual(snap.provider, .statuspage)
        XCTAssertFalse(recording.requested.map(\.absoluteString).contains(eventsURL))
    }

    func testUnchangedBodySkipsParse() async throws {
        let client = eventsClient()
        let page = URL(string: "https://health.aws.amazon.com/health/status")!
        ProviderProbe.resetCounts()
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .aws)
        XCTAssertEqual(first.body, Data("HTTP 200\n".utf8) + emptyJSON)
        XCTAssertGreaterThan(ProviderProbe.parseCount, 0)
        ProviderProbe.resetCounts()
        let second = try await ProviderProbe.probeHit(
            pageURL: page,
            client: client,
            prefer: .aws,
            previousBody: first.body,
            previousSnapshot: first.snapshot
        )
        XCTAssertEqual(ProviderProbe.parseCount, 0)
        XCTAssertEqual(second.snapshot, first.snapshot)
    }

    func testHTTPStatusChangeWithSameBytesDoesNotReuseSnapshot() async throws {
        var client = eventsClient()
        let page = URL(string: "https://health.aws.amazon.com/health/status")!
        let first = try await ProviderProbe.probeHit(pageURL: page, client: client, prefer: .aws)
        XCTAssertEqual(first.snapshot.overall, .green)
        client.byURL[eventsURL] = (emptyJSON, 503)
        do {
            let second = try await ProviderProbe.probeHit(
                pageURL: page,
                client: client,
                prefer: .aws,
                previousBody: first.body,
                previousSnapshot: first.snapshot
            )
            XCTFail("expected unreachable, reused \(second.snapshot.overall)")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
    }

    func testCurrentEvents503IsUnreachable() async {
        let recording = RecordingHTTPClient(eventsClient(status: 503, body: Data()))
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://health.aws.amazon.com/health/status")!,
                client: recording
            )
            XCTFail("expected unreachable")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unreachable)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL])
    }

    func testCurrentEventsHTMLIsUnsupported() async {
        let recording = RecordingHTTPClient(
            eventsClient(body: Data("<html>no</html>".utf8))
        )
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://health.aws.amazon.com/health/status")!,
                client: recording
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL])
    }

    func testLandingMissDoesNotFallThroughToStatuspage() async {
        var inner = eventsClient(status: 404, body: Data())
        inner.byURL["https://health.aws.amazon.com/health/status/api/v2/summary.json"] = (
            Data("""
            {
              "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
              "status": {"indicator": "none"},
              "components": [],
              "incidents": []
            }
            """.utf8),
            200
        )
        let recording = RecordingHTTPClient(inner)
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://health.aws.amazon.com/health/status")!,
                client: recording
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertEqual(recording.requested.map(\.absoluteString), [eventsURL])
    }

    func testUTF16CurrentEventsParses() async throws {
        let json = "[]"
        var data = Data([0xFE, 0xFF])
        data.append(contentsOf: json.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] })
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://health.aws.amazon.com/health/status")!,
            client: eventsClient(body: data)
        )
        XCTAssertEqual(snap.provider, .aws)
        XCTAssertEqual(snap.name, "AWS")
        XCTAssertEqual(snap.overall, .green)
    }

    private func eventsClient(status: Int = 200, body: Data? = nil) -> MapHTTPClient {
        var client = MapHTTPClient()
        client.byURL[eventsURL] = (body ?? emptyJSON, status)
        return client
    }
}
