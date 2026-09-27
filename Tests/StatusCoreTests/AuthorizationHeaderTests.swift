import XCTest
@testable import StatusCore
import TestSupport

/// FT-45-01 / FT-45-02: probe Authorization header for page read token (REQ-45).
final class AuthorizationHeaderTests: XCTestCase {
    func testWhenTokenIsSetHeaderIsBearerToken() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: "abc"),
            ["Authorization": "Bearer abc"]
        )
    }

    func testWhenTokenIsNilHeaderMapIsEmpty() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: nil),
            [:]
        )
    }

    func testWhenTokenIsEmptyStringHeaderMapIsEmpty() {
        XCTAssertEqual(
            RequestHeaders.authorization(token: ""),
            [:]
        )
    }

    /// FT-45-01: probe must attach the same header map on each same-origin GET.
    func testProbeHeaderMapMatchesAuthorizationHelper() {
        let token = "page-read-token"
        let expected = RequestHeaders.authorization(token: token)
        XCTAssertEqual(expected["Authorization"], "Bearer \(token)")
        XCTAssertEqual(expected.count, 1)
    }

    func testProbeSendsBearerHeaderOnEveryGet() async {
        let client = MapHTTPClient()
        do {
            _ = try await ProviderProbe.probe(
                pageURL: URL(string: "https://example.com")!,
                token: "abc",
                client: client
            )
            XCTFail("expected unsupported")
        } catch {
            XCTAssertEqual(error as? ProbeError, .unsupported)
        }
        XCTAssertFalse(client.recordedHeaders.isEmpty)
        let expected = RequestHeaders.authorization(token: "abc")
        for headers in client.recordedHeaders {
            XCTAssertEqual(headers, expected)
        }
    }

    func testProbeDoesNotSendPageTokenToAzureFeed() async {
        let client = MapHTTPClient()
        _ = try? await ProviderProbe.probe(
            pageURL: URL(string: "https://status.cloud.microsoft")!,
            token: "private-page-token",
            client: client
        )
        let requests = zip(client.recordedURLs, client.recordedHeaders)
        XCTAssertTrue(requests.contains { $0.0.host == "rssfeed.azure.status.microsoft" })
        for (url, headers) in requests {
            if url.host == "rssfeed.azure.status.microsoft" {
                XCTAssertNil(headers["Authorization"])
            }
        }
    }

    func testProbeSendsNoAuthorizationWhenTokenIsNil() async {
        let client = MapHTTPClient()
        _ = try? await ProviderProbe.probe(
            pageURL: URL(string: "https://example.com")!,
            client: client
        )
        XCTAssertFalse(client.recordedHeaders.isEmpty)
        for headers in client.recordedHeaders {
            XCTAssertEqual(headers, [:])
        }
    }

    func testProbeSendsNoAuthorizationWhenTokenIsEmpty() async {
        let client = MapHTTPClient()
        _ = try? await ProviderProbe.probe(
            pageURL: URL(string: "https://example.com")!,
            token: "",
            client: client
        )
        XCTAssertFalse(client.recordedHeaders.isEmpty)
        for headers in client.recordedHeaders {
            XCTAssertEqual(headers, [:])
        }
    }

    /// FT-45-03: query strings stay stripped. The token is not put in the query.
    func testProbeStripsQueryAndKeepsTokenOutOfURL() async throws {
        let json = """
        {
          "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
          "status": {"indicator": "none"},
          "components": [],
          "incidents": []
        }
        """
        let client = MapHTTPClient(byPath: [
            "/api/v2/summary.json": (Data(json.utf8), 200)
        ])
        _ = try await ProviderProbe.probe(
            pageURL: URL(string: "https://www.githubstatus.com/?q=1")!,
            token: "secret-token",
            client: client
        )
        XCTAssertFalse(client.recordedURLs.isEmpty)
        for url in client.recordedURLs {
            XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query)
            XCTAssertFalse(url.absoluteString.contains("secret-token"))
        }
        XCTAssertEqual(client.lastHeaders, RequestHeaders.authorization(token: "secret-token"))
    }
}
