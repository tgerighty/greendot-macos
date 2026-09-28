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
    static func allows(_ url: URL?, from original: URL?) -> Bool {
        guard let original, let next = url else { return false }
        guard let fromOrigin = origin(original), let toOrigin = origin(next) else { return false }
        if fromOrigin == toOrigin { return true }
        return fromOrigin.host == toOrigin.host
            && fromOrigin.scheme == "http"
            && toOrigin.scheme == "https"
            && fromOrigin.port == 80
            && toOrigin.port == 443
    }

    static func origin(_ url: URL) -> Origin? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return nil
        }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        return Origin(scheme: scheme, host: host, port: port)
    }

    struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int
    }
}

public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (Data, Int)
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
    func getLocated(_ url: URL) async throws -> HTTPGet
    func getLocated(_ url: URL, headers: [String: String]) async throws -> HTTPGet
}

public enum HTTPClientError: Error {
    case headersUnsupported
}

extension HTTPClient {
    /// Legacy clients must reject headers. Token-aware clients override this method.
    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        if !headers.isEmpty { throw HTTPClientError.headersUnsupported }
        return try await get(url)
    }

    public func getLocated(_ url: URL) async throws -> HTTPGet {
        let (data, status) = try await get(url)
        return HTTPGet(data: data, status: status, url: url)
    }

    public func getLocated(_ url: URL, headers: [String: String]) async throws -> HTTPGet {
        let (data, status) = try await get(url, headers: headers)
        return HTTPGet(data: data, status: status, url: url)
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    let rateLimit = RateLimitGate()

    public init(session: URLSession) {
        let delegate = SameOriginRedirectDelegate()
        self.session = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    public init() {
        let delegate = SameOriginRedirectDelegate()
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

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        let hit = try await getLocated(url, headers: headers)
        return (hit.data, hit.status)
    }

    public func getLocated(_ url: URL) async throws -> HTTPGet {
        try await getLocated(url, headers: [:])
    }

    public func getLocated(_ url: URL, headers: [String: String]) async throws -> HTTPGet {
        let requested = HTTPAuth.requestURL(url)
        if let held = rateLimit.cached(requested) {
            return held
        }
        var request = URLRequest(url: requested)
        let requestHeaders = HTTPAuth.headers(for: url).merging(headers) { _, requested in requested }
        for (field, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let final = response.url ?? requested
        guard RedirectPolicy.allows(final, from: requested) else {
            return HTTPGet(data: Data(), status: 0, url: url)
        }
        let hit = HTTPGet(data: data, status: status, url: final)
        return rateLimit.receive(
            requested,
            response: hit,
            retryAfter: http?.value(forHTTPHeaderField: "Retry-After")
        )
    }
}

struct RequestHeaderHTTPClient: HTTPClient {
    let base: HTTPClient
    let headers: [String: String]
    let pageURL: URL

    private func scopedHeaders(for url: URL) -> [String: String] {
        RedirectPolicy.allows(url, from: pageURL) ? headers : [:]
    }

    func get(_ url: URL) async throws -> (Data, Int) {
        try await base.get(url, headers: scopedHeaders(for: url))
    }

    func get(_ url: URL, headers additional: [String: String]) async throws -> (Data, Int) {
        try await base.get(url, headers: scopedHeaders(for: url).merging(additional) { _, next in next })
    }

    func getLocated(_ url: URL) async throws -> HTTPGet {
        try await base.getLocated(url, headers: scopedHeaders(for: url))
    }

    func getLocated(_ url: URL, headers additional: [String: String]) async throws -> HTTPGet {
        try await base.getLocated(url, headers: scopedHeaders(for: url).merging(additional) { _, next in next })
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
        let allowed = RedirectPolicy.allows(
            newRequest.url,
            from: response.url ?? task.originalRequest?.url
        )
        completionHandler(allowed ? newRequest : nil)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let url = task.originalRequest?.url ?? task.currentRequest?.url,
           TLSTrust.allowsInsecureServerTrust(for: url),
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
