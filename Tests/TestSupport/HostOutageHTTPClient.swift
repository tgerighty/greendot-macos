import Foundation
import StatusCore

/// Fails every request to a host in `offlineHosts` and answers the rest with a green page.
public final class HostOutageHTTPClient: HTTPClient, @unchecked Sendable {
    private let greenJSON: Data
    private let lock = NSLock()
    private var storedOfflineHosts: Set<String> = []

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

    public func get(_ url: URL) async throws -> (Data, Int) {
        guard let host = url.host, !offlineHosts.contains(host) else {
            throw URLError(.notConnectedToInternet)
        }
        guard url.path == "/api/v2/summary.json" else { return (Data(), 404) }
        return (greenJSON, 200)
    }
}
