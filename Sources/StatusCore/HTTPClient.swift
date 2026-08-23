import Foundation

public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

public struct MapHTTPClient: HTTPClient, Sendable {
    public var byPath: [String: (Data, Int)]
    public var byURL: [String: (Data, Int)]

    public init(byPath: [String: (Data, Int)] = [:]) {
        self.byPath = byPath
        self.byURL = [:]
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        if let hit = byURL[url.absoluteString] { return hit }
        if let hit = byPath[url.path] { return hit }
        return (Data(), 404)
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
