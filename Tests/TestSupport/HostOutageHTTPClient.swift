import Foundation
import StatusCore

/// Fails every request to a host in `offlineHosts` and answers the rest with a green page.
public final class HostOutageHTTPClient: HTTPClient, @unchecked Sendable {
    private let greenJSON: Data
    private let lock = NSLock()
    private var storedOfflineHosts: Set<String> = []
    private var storedRequestCount = 0
    private var storedHostCounts: [String: Int] = [:]
    private var storedFailAfterCount: Int?
    private var storedHangWhenHostCountExceeds: [String: Int] = [:]

    public init(greenJSON: Data) {
        self.greenJSON = greenJSON
    }

    public var offlineHosts: Set<String> {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedOfflineHosts
        }
        set {
            lock.lock()
            storedOfflineHosts = newValue
            lock.unlock()
        }
    }

    public var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    /// Drops the network after this many requests have already been served. A test uses this to
    /// land a failure while a poll is in flight.
    public var failAfterCount: Int? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedFailAfterCount
        }
        set {
            lock.lock()
            storedFailAfterCount = newValue
            lock.unlock()
        }
    }

    /// Lets a test stall a later request to a host that already answered, so the confirmation
    /// timeout can be exercised without stalling the poll itself.
    public var hangWhenHostCountExceeds: [String: Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedHangWhenHostCountExceeds
        }
        set {
            lock.lock()
            storedHangWhenHostCountExceeds = newValue
            lock.unlock()
        }
    }

    public func requestCount(for host: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storedHostCounts[host] ?? 0
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        let (shouldHang, shouldFail) = beginRequest(host: url.host)
        if shouldHang {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        guard url.path == "/api/v2/summary.json" else { return (Data(), 404) }
        return (greenJSON, 200)
    }

    private func beginRequest(host: String?) -> (hang: Bool, fail: Bool) {
        lock.lock()
        defer { lock.unlock() }
        storedRequestCount += 1
        var hostCount = 0
        if let host {
            hostCount = storedHostCounts[host, default: 0] + 1
            storedHostCounts[host] = hostCount
        }
        let shouldHang: Bool
        if let host, let threshold = storedHangWhenHostCountExceeds[host] {
            shouldHang = hostCount > threshold
        } else {
            shouldHang = false
        }
        let overFailLimit = storedFailAfterCount.map { storedRequestCount > $0 } ?? false
        let hostOffline = host.map { storedOfflineHosts.contains($0) } ?? true
        return (shouldHang, overFailLimit || hostOffline)
    }
}
