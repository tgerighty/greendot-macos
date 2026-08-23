import Foundation

public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
}

extension HTTPClient {
    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await get(url)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        try await send(url, headers: [:])
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await send(url, headers: headers)
    }

    private func send(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

public struct MapHTTPClient: HTTPClient, @unchecked Sendable {
    public var byPath: [String: (Data, Int)]
    public var byURL: [String: (Data, Int)]
    private let recorded = RequestLog()

    public init(byPath: [String: (Data, Int)] = [:]) {
        self.byPath = byPath
        self.byURL = [:]
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        lookup(url)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        recorded.urls.append(url)
        recorded.headers.append(headers)
        return lookup(url)
    }

    private func lookup(_ url: URL) -> (Data, Int) {
        if let hit = byURL[url.absoluteString] { return hit }
        if let hit = byPath[url.path] { return hit }
        return (Data(), 404)
    }

    public var lastHeaders: [String: String] { recorded.headers.last ?? [:] }
    public var recordedHeaders: [[String: String]] { recorded.headers }
    public var recordedURLs: [URL] { recorded.urls }
}

/// Records GET header maps for tests. MapHTTPClient does not use headers for routing.
private final class RequestLog: @unchecked Sendable {
    var urls: [URL] = []
    var headers: [[String: String]] = []
}
