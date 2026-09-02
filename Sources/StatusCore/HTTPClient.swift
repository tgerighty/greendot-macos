import Foundation

public struct HTTPGet: Sendable {
    public let data: Data
    public let status: Int
    public let url: URL

    public init(data: Data, status: Int, url: URL) {
        self.data = data
        self.status = status
        self.url = url
    }
}

enum RedirectPolicy {
    static func allows(_ request: URLRequest, from original: URL?) -> Bool {
        guard let originalHost = original?.host?.lowercased() else { return false }
        guard let nextHost = request.url?.host?.lowercased() else { return false }
        return originalHost == nextHost
    }
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
    private let redirectDelegate: SameOriginRedirectDelegate?

    public init(session: URLSession) {
        self.session = session
        self.redirectDelegate = nil
    }

    public init() {
        let delegate = SameOriginRedirectDelegate()
        self.redirectDelegate = delegate
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        let hit = try await getLocated(url)
        return (hit.data, hit.status)
    }

    public func getLocated(_ url: URL) async throws -> HTTPGet {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let final = response.url ?? url
        if RedirectPolicy.allows(URLRequest(url: final), from: url) {
            return HTTPGet(data: data, status: status, url: final)
        }
        return HTTPGet(data: Data(), status: 0, url: url)
    }
}

final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let allowed = RedirectPolicy.allows(newRequest, from: task.originalRequest?.url)
        completionHandler(allowed ? newRequest : nil)
    }
}
