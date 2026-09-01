import XCTest
@testable import StatusCore
import TestSupport

final class FlashdutyProbeTests: XCTestCase {
    private let widgetJSON = """
    {
      "schema_version": "1.0",
      "page": {"name": "DeepSeek", "url": "https://status.deepseek.com"},
      "overall": {"status": "operational"},
      "ongoing_incidents": [],
      "in_progress_maintenances": [],
      "scheduled_maintenances": []
    }
    """

    func testProbeFindsFlashduty() async throws {
        let client = MapHTTPClient(byPath: [
            "/api/widget/v1/summary.json": (Data(widgetJSON.utf8), 200)
        ])
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.deepseek.com")!,
            client: client
        )
        XCTAssertEqual(snap.provider, .flashduty)
        XCTAssertEqual(snap.name, "DeepSeek")
    }

    func testProbePrefersFlashdutyWidgetEndpoint() async throws {
        var inner = MapHTTPClient()
        inner.byURL["https://status.deepseek.com/api/widget/v1/summary.json"] = (Data(widgetJSON.utf8), 200)
        let recording = RecordingHTTPClient(inner)
        let snap = try await ProviderProbe.probe(
            pageURL: URL(string: "https://status.deepseek.com")!,
            client: recording,
            prefer: .flashduty
        )
        XCTAssertEqual(snap.provider, .flashduty)
        XCTAssertEqual(recording.requested.map(\.absoluteString), [
            "https://status.deepseek.com/api/widget/v1/summary.json"
        ])
    }
}
