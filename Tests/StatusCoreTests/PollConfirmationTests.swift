import XCTest
@testable import StatusCore
import TestSupport

final class PollConfirmationTests: XCTestCase {
    private let greenJSON = Data("""
    {
      "page": {"name": "GitHub", "url": "https://www.githubstatus.com"},
      "status": {"indicator": "none"},
      "components": [{"name": "API", "status": "operational", "group": false}],
      "incidents": []
    }
    """.utf8)

    /// A drop that lands while a poll is in flight used to emit one grey toast per failed page.
    /// Confirming a page that just answered collapses that first mixed poll to the lost toast.
    func testMidPollDropCollapsesToOneLostToast() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client)
        defer { try? FileManager.default.removeItem(at: directory) }

        client.failAfterCount = 1
        let lost = try await monitor.pollAll()
        XCTAssertEqual(lost, [NetworkToast.lost])
        XCTAssertTrue(monitor.showingNetworkLoss)
        XCTAssertTrue(monitor.pages.allSatisfy { $0.snapshot?.isUnreachable == true })

        let stillLost = try await monitor.pollAll()
        XCTAssertEqual(stillLost, [])
    }

    func testGenuineSiteOutageKeepsPageToastAndConfirmsOnce() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client)
        defer { try? FileManager.default.removeItem(at: directory) }

        client.offlineHosts = ["b.example"]
        let toasts = try await monitor.pollAll()

        XCTAssertEqual(toasts.map(\.pageName), ["B"])
        XCTAssertEqual(toasts.map(\.body), ["Unreachable"])
        XCTAssertFalse(monitor.showingNetworkLoss)
        XCTAssertEqual(monitor.pages[0].snapshot?.isUnreachable, false)
        XCTAssertEqual(monitor.pages[1].snapshot?.isUnreachable, true)
        XCTAssertEqual(client.requestCount(for: "a.example"), 2)
    }

    func testSteadyHealthyPollMakesNoConfirmationRequest() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await monitor.pollAll()
        XCTAssertEqual(first, [])
        XCTAssertEqual(client.requestCount, 2)
        let second = try await monitor.pollAll()
        XCTAssertEqual(second, [])
        XCTAssertEqual(client.requestCount, 4)
    }

    func testLongRunningSiteOutageMakesNoConfirmationRequest() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client)
        defer { try? FileManager.default.removeItem(at: directory) }

        client.offlineHosts = ["b.example"]
        _ = try await monitor.pollAll()
        let aAfterFirst = client.requestCount(for: "a.example")
        let totalAfterFirst = client.requestCount
        XCTAssertEqual(aAfterFirst, 2)

        _ = try await monitor.pollAll()
        XCTAssertEqual(client.requestCount(for: "a.example"), aAfterFirst + 1)
        let steadyCost = client.requestCount - totalAfterFirst

        _ = try await monitor.pollAll()
        XCTAssertEqual(client.requestCount - totalAfterFirst - steadyCost, steadyCost)
    }

    func testHungConfirmationDoesNotStallOrInventAnOutage() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client, confirmationTimeout: 0.05)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await monitor.pollAll()
        client.offlineHosts = ["b.example"]
        client.hangWhenHostCountExceeds = ["a.example": 2]

        let started = Date()
        let toasts = try await monitor.pollAll()
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertGreaterThan(elapsed, 0.02)
        XCTAssertLessThan(elapsed, 1)
        XCTAssertEqual(toasts.map(\.pageName), ["B"])
        XCTAssertEqual(toasts.map(\.body), ["Unreachable"])
        XCTAssertFalse(monitor.showingNetworkLoss)
        XCTAssertEqual(monitor.pages[0].snapshot?.isUnreachable, false)
        XCTAssertEqual(monitor.pages[1].snapshot?.isUnreachable, true)
    }

    /// The confirmation probe runs outside the task group of the poll. A cancelled poll must still
    /// end at once, and it must report the cancellation rather than a result.
    func testCancellingAPollDuringConfirmationThrows() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(client: client, confirmationTimeout: 30)
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try await monitor.pollAll()
        client.offlineHosts = ["b.example"]
        client.hangWhenHostCountExceeds = ["a.example": 2]

        let poll = Task { try await monitor.pollAll() }
        while client.requestCount(for: "a.example") < 3 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        poll.cancel()

        do {
            _ = try await poll.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testConfirmationReprobesTheFirstReachablePageInWatchOrder() async throws {
        let client = HostOutageHTTPClient(greenJSON: greenJSON)
        let (monitor, directory) = try seededMonitor(
            client: client,
            hosts: ["a.example", "b.example", "c.example"]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        client.offlineHosts = ["a.example"]
        _ = try await monitor.pollAll()

        XCTAssertEqual(client.requestCount(for: "b.example"), 2)
        XCTAssertEqual(client.requestCount(for: "c.example"), 1)
        XCTAssertFalse(monitor.showingNetworkLoss)
    }

    /// A public caller can pass any TimeInterval. The confirmation sleep converts the timeout to
    /// UInt64, which traps on a negative, a NaN, or a value too large for UInt64. Monitor must
    /// make the stored timeout safe.
    func testInvalidConfirmationTimeoutBecomesASafeValue() throws {
        let cases: [(given: TimeInterval, stored: TimeInterval)] = [
            (-1, Monitor.defaultConfirmationTimeout),
            (0, Monitor.defaultConfirmationTimeout),
            (.nan, Monitor.defaultConfirmationTimeout),
            (.infinity, Monitor.defaultConfirmationTimeout),
            (.greatestFiniteMagnitude, Monitor.maxConfirmationTimeout),
            (1e18, Monitor.maxConfirmationTimeout),
            (0.05, 0.05)
        ]
        for testCase in cases {
            let client = HostOutageHTTPClient(greenJSON: greenJSON)
            let (monitor, directory) = try seededMonitor(client: client, confirmationTimeout: testCase.given)
            defer { try? FileManager.default.removeItem(at: directory) }
            XCTAssertEqual(monitor.confirmationTimeout, testCase.stored, "timeout \(testCase.given)")
        }
    }

    /// A poll that confirms a mixed result runs the timeout sleep. A bad timeout must not trap it.
    func testPollWithInvalidConfirmationTimeoutStillCompletes() async throws {
        for timeout in [-1, TimeInterval.nan, .greatestFiniteMagnitude] {
            let client = HostOutageHTTPClient(greenJSON: greenJSON)
            let (monitor, directory) = try seededMonitor(client: client, confirmationTimeout: timeout)
            defer { try? FileManager.default.removeItem(at: directory) }

            client.offlineHosts = ["b.example"]
            let toasts = try await monitor.pollAll()

            XCTAssertEqual(toasts.map(\.pageName), ["B"], "timeout \(timeout)")
            XCTAssertEqual(client.requestCount(for: "a.example"), 2, "timeout \(timeout)")
        }
    }

    private func seededMonitor(
        client: HTTPClient,
        hosts: [String] = ["a.example", "b.example"],
        confirmationTimeout: TimeInterval = 3
    ) throws -> (Monitor, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PageStore(directory: directory)
        var config = AppConfig()
        config.pages = hosts.map { host in
            BenchmarkFixtures.greenPage(
                host: host,
                name: String(host.prefix(1)).uppercased(),
                provider: .statuspage
            )
        }
        try store.save(config)
        let monitor = Monitor(store: store, client: client, confirmationTimeout: confirmationTimeout)
        try monitor.load()
        return (monitor, directory)
    }
}
