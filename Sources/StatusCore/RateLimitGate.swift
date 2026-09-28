import Foundation

/// How long to wait after HTTP 429. Requesting again before this refreshes the server wait.
enum RetryAfterDelay {
    static let fallback: TimeInterval = 60
    static let limit: TimeInterval = 300

    static func seconds(from header: String?, now: Date) -> TimeInterval {
        guard let header else { return fallback }
        let text = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        if let seconds = TimeInterval(text), seconds.isFinite {
            if seconds <= 0 { return 0 }
            return min(seconds, limit)
        }
        guard let date = httpDate(from: text) else { return fallback }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return 0 }
        return min(delta, limit)
    }

    private static func httpDate(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}

/// A 429 keeps the last small 200 and serves it until Retry-After has passed.
final class RateLimitGate: @unchecked Sendable {
    var now: () -> Date = { Date() }

    static let maxCachedBytes = 64 * 1024

    private let lock = NSLock()
    private var quietUntil: [String: Date] = [:]
    private var lastOK: [String: HTTPGet] = [:]

    /// A held response means do not touch the network. Nil means the wait is over.
    func cached(_ url: URL) -> HTTPGet? {
        lock.lock()
        defer { lock.unlock() }
        let key = url.absoluteString
        guard let until = quietUntil[key] else { return nil }
        let current = now()
        if current >= until {
            quietUntil[key] = nil
            return nil
        }
        return lastOK[key] ?? HTTPGet(data: Data(), status: 429, url: url)
    }

    /// Stores a 200, and on 429 returns that 200 instead of the refusal when one exists.
    func receive(_ requested: URL, response: HTTPGet, retryAfter: String?) -> HTTPGet {
        lock.lock()
        defer { lock.unlock() }
        let key = requested.absoluteString
        if response.status == 200 {
            quietUntil[key] = nil
            if response.data.count <= Self.maxCachedBytes {
                lastOK[key] = response
            } else {
                lastOK[key] = nil
            }
            return response
        }
        guard response.status == 429 else { return response }
        let current = now()
        let wait = RetryAfterDelay.seconds(from: retryAfter, now: current)
        if wait > 0 {
            quietUntil[key] = current.addingTimeInterval(wait)
        }
        return lastOK[key] ?? response
    }
}

/// Parallel polls of one URL share one request, so a second caller cannot draw a 429.
final class InFlightGate: @unchecked Sendable {
    private struct Entry {
        let entryID: UUID
        let task: Task<HTTPGet, Error>
    }

    private let lock = NSLock()
    private var tasks: [String: Entry] = [:]

    func run(
        _ key: String,
        _ work: @escaping @Sendable () async throws -> HTTPGet
    ) async throws -> HTTPGet {
        let entryID = UUID()
        if let existing = currentTask(key) {
            return try await existing.value
        }
        let created = Task { try await work() }
        if let winner = claim(key, entryID: entryID, task: created) {
            created.cancel()
            return try await winner.value
        }
        do {
            let value = try await created.value
            finish(key, entryID)
            return value
        } catch {
            finish(key, entryID)
            throw error
        }
    }

    private func currentTask(_ key: String) -> Task<HTTPGet, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[key]?.task
    }

    /// Stores `task` when the key is free. Returns the task that won when another caller arrived first.
    private func claim(_ key: String, entryID: UUID, task: Task<HTTPGet, Error>) -> Task<HTTPGet, Error>? {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tasks[key] {
            return existing.task
        }
        tasks[key] = Entry(entryID: entryID, task: task)
        return nil
    }

    private func finish(_ key: String, _ entryID: UUID) {
        lock.lock()
        if tasks[key]?.entryID == entryID {
            tasks[key] = nil
        }
        lock.unlock()
    }
}
