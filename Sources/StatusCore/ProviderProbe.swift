import Foundation

public enum ProbeError: Error, Equatable, LocalizedError {
    case unsupported
    case unreachable

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This URL is not a known status page format (Statuspage, Statuspal, or Instatus)."
        case .unreachable:
            return "Could not reach that URL."
        }
    }
}

public enum ProviderProbe {
    static var parseCount: Int { parseBox.current }
    static var regexCompileCount: Int { regexBox.current }

    static func resetCounts() {
        parseBox.reset()
        regexBox.reset()
    }

    public static func probe(
        pageURL: URL,
        client: HTTPClient,
        prefer: StatusProvider? = nil
    ) async throws -> PageSnapshot {
        try await probeHit(pageURL: pageURL, client: client, prefer: prefer).snapshot
    }

    static func probeHit(
        pageURL: URL,
        client: HTTPClient,
        prefer: StatusProvider? = nil,
        previousBody: Data? = nil,
        previousSnapshot: PageSnapshot? = nil
    ) async throws -> ProbeHit {
        let base = normalizedBase(pageURL)
        var sawHTTP = false
        var sawNetworkError = false

        func take(_ result: AttemptResult) -> ProbeHit? {
            switch result {
            case .hit(let snapshot, let data):
                return ProbeHit(snapshot: snapshot, body: data)
            case .miss:
                sawHTTP = true
                return nil
            case .networkError:
                sawNetworkError = true
                return nil
            }
        }

        func tryStatuspage() async throws -> ProbeHit? {
            take(try await attempt(
                base.appendingPathComponent("api/v2/summary.json"),
                client: client,
                previousBody: previousBody,
                previousSnapshot: previousSnapshot,
                parse: { try StatuspageParser.parse(data: $0, sourceURL: base) }
            ))
        }

        func tryInstatus() async throws -> ProbeHit? {
            take(try await attempt(
                base.appendingPathComponent("summary.json"),
                client: client,
                previousBody: previousBody,
                previousSnapshot: previousSnapshot,
                parse: { try InstatusParser.parse(data: $0, sourceURL: base) }
            ))
        }

        func tryStatuspal() async throws -> ProbeHit? {
            try await probeStatuspal(
                base: base,
                client: client,
                flags: &sawHTTP,
                network: &sawNetworkError,
                previousBody: previousBody,
                previousSnapshot: previousSnapshot
            )
        }

        for provider in probeOrder(preferring: prefer) {
            switch provider {
            case .statuspage:
                if let hit = try await tryStatuspage() { return hit }
            case .instatus:
                if let hit = try await tryInstatus() { return hit }
            case .statuspal:
                if let hit = try await tryStatuspal() { return hit }
            }
        }
        if !sawHTTP && sawNetworkError {
            throw ProbeError.unreachable
        }
        throw ProbeError.unsupported
    }

    static func probeOrder(preferring prefer: StatusProvider?) -> [StatusProvider] {
        switch prefer {
        case .none, .statuspage:
            return [.statuspage, .instatus, .statuspal]
        case .instatus:
            return [.instatus, .statuspage, .statuspal]
        case .statuspal:
            return [.statuspal, .statuspage, .instatus]
        }
    }

    public static func normalizedBase(_ url: URL) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        if parts.scheme == nil {
            parts.scheme = "https"
        }
        parts.query = nil
        parts.fragment = nil
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        parts.path = path
        return parts.url ?? url
    }

    private enum AttemptResult {
        case hit(PageSnapshot, Data)
        case miss
        case networkError
    }

    private static func attempt(
        _ url: URL,
        client: HTTPClient,
        previousBody: Data?,
        previousSnapshot: PageSnapshot?,
        parse: (Data) throws -> PageSnapshot
    ) async throws -> AttemptResult {
        do {
            let (data, status) = try await client.get(url)
            try Task.checkCancellation()
            guard status == 200 else { return .miss }
            if let previousBody, let previousSnapshot,
               !previousSnapshot.isUnreachable,
               data == previousBody {
                return .hit(previousSnapshot, data)
            }
            do {
                parseBox.increment()
                return .hit(try parse(data), data)
            } catch {
                return .miss
            }
        } catch {
            try throwIfCancelled(error)
            return .networkError
        }
    }

    private static func probeStatuspal(
        base: URL,
        client: HTTPClient,
        flags sawHTTP: inout Bool,
        network sawNetworkError: inout Bool,
        previousBody: Data?,
        previousSnapshot: PageSnapshot?
    ) async throws -> ProbeHit? {
        let host = base.host ?? ""
        var subdomains: [String] = []
        if host.hasSuffix(".statuspal.io") || host.hasSuffix(".statuspal.eu") {
            subdomains.append(host.split(separator: ".").first.map(String.init) ?? host)
        }
        if subdomains.isEmpty {
            do {
                let htmlHit = try await client.get(base)
                try Task.checkCancellation()
                sawHTTP = true
                if htmlHit.1 == 200,
                   let html = String(data: htmlHit.0, encoding: .utf8),
                   html.lowercased().contains("statuspal"),
                   let extracted = extractStatuspalSubdomain(from: html) {
                    subdomains.append(extracted)
                }
            } catch {
                try throwIfCancelled(error)
                sawNetworkError = true
            }
        }
        let unique = Array(NSOrderedSet(array: subdomains)) as? [String] ?? subdomains
        let apiHosts = ["https://statuspal.io/api/v2/status_pages/", "https://statuspal.eu/api/v2/status_pages/"]
        for subdomain in unique {
            for prefix in apiHosts {
                guard let url = URL(string: prefix + subdomain + "/summary") else { continue }
                switch try await attempt(
                    url,
                    client: client,
                    previousBody: previousBody,
                    previousSnapshot: previousSnapshot,
                    parse: { try StatuspalParser.parse(data: $0, sourceURL: base) }
                ) {
                case .hit(let snapshot, let data):
                    return ProbeHit(snapshot: snapshot, body: data)
                case .miss:
                    sawHTTP = true
                case .networkError:
                    sawNetworkError = true
                }
            }
        }
        return nil
    }

    private static func throwIfCancelled(_ error: Error) throws {
        guard !(error is CancellationError || Task.isCancelled) else {
            throw CancellationError()
        }
    }

    private static let statuspalRegex: NSRegularExpression? = {
        regexBox.increment()
        return try? NSRegularExpression(
            pattern: "statuspal\\.(?:io|eu)/api/v2/status_pages/([A-Za-z0-9_-]+)",
            options: [.caseInsensitive]
        )
    }()

    static func extractStatuspalSubdomain(from html: String) -> String? {
        guard let regex = statuspalRegex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let inner = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[inner])
    }
}

struct ProbeHit: Sendable {
    let snapshot: PageSnapshot
    let body: Data
}

private final class CountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private let parseBox = CountBox()
private let regexBox = CountBox()
