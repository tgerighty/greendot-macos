import Foundation
import StatusCore

public final class ControllableHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    private var waiters: [(minimum: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init() {
        // Requests are registered only when get(_:) is called.
    }

    public func get(_: URL) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            requestCount += 1
            let request = requestCount
            pending[request] = continuation
            let ready = waiters.filter { requestCount >= $0.minimum }
            waiters.removeAll { requestCount >= $0.minimum }
            lock.unlock()
            ready.forEach { $0.continuation.resume() }
        }
    }

    public func waitUntilRequestCount(_ minimum: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if requestCount >= minimum {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((minimum: minimum, continuation: continuation))
                lock.unlock()
            }
        }
    }

    public func complete(request: Int, with data: Data) {
        lock.lock()
        guard let continuation = pending.removeValue(forKey: request) else {
            lock.unlock()
            assertionFailure("Unknown HTTP request ordinal: \(request)")
            return
        }
        lock.unlock()
        continuation.resume(returning: (data, 200))
    }

    public func failAll(_ error: Error = URLError(.cancelled)) {
        lock.lock()
        let continuations = Array(pending.values)
        let waiterContinuations = waiters.map { $0.continuation }
        pending.removeAll()
        waiters.removeAll()
        lock.unlock()

        continuations.forEach { $0.resume(throwing: error) }
        waiterContinuations.forEach { $0.resume() }
    }
}
