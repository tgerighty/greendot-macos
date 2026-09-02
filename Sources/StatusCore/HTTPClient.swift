import Foundation

public struct HTTPGet: Sendable {
    public let data: Data
    public let status: Int
    public let url: URL
}

public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)
    func getLocated(_ url: URL) async throws -> HTTPGet
}

extension HTTPClient {
    public func getLocated(_ url: URL) async throws -> HTTPGet {
        let (data, status) = try await get(url)
        return HTTPGet(data: data, status: status, url: url)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        let hit = try await getLocated(url)
        return (hit.data, hit.status)
    }

    public func getLocated(_ url: URL) async throws -> HTTPGet {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPGet(data: data, status: status, url: response.url ?? url)
    }
}
