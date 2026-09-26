import Foundation
import StatusCore

public struct MapHTTPClient: HTTPClient, @unchecked Sendable {
    public var byPath: [String: (Data, Int)]
    public var byURL: [String: (Data, Int)]
    private let recorded = RecordedRequests()

    public init(byPath: [String: (Data, Int)] = [:]) {
        self.byPath = byPath
        self.byURL = [:]
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        recorded.add(url, headers: [:])
        return lookup(url)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        recorded.add(url, headers: headers)
        return lookup(url)
    }

    public func getLocated(_ url: URL, headers: [String: String]) async throws -> HTTPGet {
        let (data, status) = try await get(url, headers: headers)
        return HTTPGet(data: data, status: status, url: url)
    }

    private func lookup(_ url: URL) -> (Data, Int) {
        if let hit = byURL[url.absoluteString] { return hit }
        if let hit = byPath[url.path] { return hit }
        return (Data(), 404)
    }

    public var recordedHeaders: [[String: String]] { recorded.headers }
    public var recordedURLs: [URL] { recorded.urls }
    public var lastHeaders: [String: String] { recorded.headers.last ?? [:] }
}

private final class RecordedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var storedURLs: [URL] = []
    private var storedHeaders: [[String: String]] = []

    func add(_ url: URL, headers: [String: String]) {
        lock.lock()
        storedURLs.append(url)
        storedHeaders.append(headers)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedURLs
    }

    var headers: [[String: String]] {
        lock.lock()
        defer { lock.unlock() }
        return storedHeaders
    }
}

public struct DelayHTTPClient: HTTPClient, Sendable {
    public let inner: any HTTPClient
    public let nanoseconds: UInt64

    public init(inner: any HTTPClient, nanoseconds: UInt64) {
        self.inner = inner
        self.nanoseconds = nanoseconds
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        try await Task.sleep(nanoseconds: nanoseconds)
        return try await inner.get(url)
    }
}

public final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private let inner: any HTTPClient
    private let recorded = RecordedURLs()

    public init(_ inner: any HTTPClient) {
        self.inner = inner
    }

    public var requested: [URL] { recorded.snapshot() }

    public func get(_ url: URL) async throws -> (Data, Int) {
        recorded.add(url)
        return try await inner.get(url)
    }
}

private final class RecordedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func add(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
