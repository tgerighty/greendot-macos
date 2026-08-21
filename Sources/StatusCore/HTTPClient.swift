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

    public init(byPath: [String: (Data, Int)] = [:], byURL: [String: (String, Int)] = [:]) {
        self.byPath = byPath
        var mapped: [String: (Data, Int)] = [:]
        for (key, value) in byURL {
            mapped[key] = (Data(value.0.utf8), value.1)
        }
        self.byURL = mapped
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        if let hit = byURL[url.absoluteString] { return hit }
        if let hit = byPath[url.path] { return hit }
        return (Data(), 404)
    }
}
