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
    public static func probe(
        pageURL: URL,
        client: HTTPClient,
        prefer: StatusProvider? = nil
    ) async throws -> PageSnapshot {
        let base = normalizedBase(pageURL)
        var sawHTTP = false
        var sawNetworkError = false

        func take(_ result: AttemptResult) -> PageSnapshot? {
            switch result {
            case .hit(let snapshot):
                return snapshot
            case .miss:
                sawHTTP = true
                return nil
            case .networkError:
                sawNetworkError = true
                return nil
            }
        }

        func tryStatuspage() async -> PageSnapshot? {
            take(await attempt(
                base.appendingPathComponent("api/v2/summary.json"),
                client: client,
                parse: { try StatuspageParser.parse(data: $0, sourceURL: base) }
            ))
        }

        func tryInstatus() async -> PageSnapshot? {
            take(await attempt(
                base.appendingPathComponent("summary.json"),
                client: client,
                parse: { try InstatusParser.parse(data: $0, sourceURL: base) }
            ))
        }

        func tryStatuspal() async -> PageSnapshot? {
            await probeStatuspal(
                base: base,
                client: client,
                flags: &sawHTTP,
                network: &sawNetworkError,
                skipHTMLIfHostKnown: prefer == .statuspal
            )
        }

        let order: [StatusProvider]
        switch prefer {
        case .none, .statuspage:
            order = [.statuspage, .instatus, .statuspal]
        case .instatus:
            order = [.instatus, .statuspage, .statuspal]
        case .statuspal:
            order = [.statuspal, .statuspage, .instatus]
        }

        for provider in order {
            switch provider {
            case .statuspage:
                if let snapshot = await tryStatuspage() { return snapshot }
            case .instatus:
                if let snapshot = await tryInstatus() { return snapshot }
            case .statuspal:
                if let snapshot = await tryStatuspal() { return snapshot }
            }
        }
        if !sawHTTP && sawNetworkError {
            throw ProbeError.unreachable
        }
        throw ProbeError.unsupported
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
        case hit(PageSnapshot)
        case miss
        case networkError
    }

    private static func attempt(
        _ url: URL,
        client: HTTPClient,
        parse: (Data) throws -> PageSnapshot
    ) async -> AttemptResult {
        do {
            let (data, status) = try await client.get(url)
            guard status == 200 else { return .miss }
            do {
                return .hit(try parse(data))
            } catch {
                return .miss
            }
        } catch {
            return .networkError
        }
    }

    private static func probeStatuspal(
        base: URL,
        client: HTTPClient,
        flags sawHTTP: inout Bool,
        network sawNetworkError: inout Bool,
        skipHTMLIfHostKnown: Bool = false
    ) async -> PageSnapshot? {
        let host = base.host ?? ""
        var subdomains: [String] = []
        if host.hasSuffix(".statuspal.io") || host.hasSuffix(".statuspal.eu") {
            subdomains.append(host.split(separator: ".").first.map(String.init) ?? host)
        }
        if subdomains.isEmpty || !skipHTMLIfHostKnown {
            do {
                let htmlHit = try await client.get(base)
                sawHTTP = true
                if htmlHit.1 == 200,
                   let html = String(data: htmlHit.0, encoding: .utf8),
                   html.lowercased().contains("statuspal"),
                   let extracted = extractStatuspalSubdomain(from: html) {
                    subdomains.append(extracted)
                }
            } catch {
                sawNetworkError = true
            }
        }
        let unique = Array(NSOrderedSet(array: subdomains)) as? [String] ?? subdomains
        let apiHosts = ["https://statuspal.io/api/v2/status_pages/", "https://statuspal.eu/api/v2/status_pages/"]
        for subdomain in unique {
            for prefix in apiHosts {
                guard let url = URL(string: prefix + subdomain + "/summary") else { continue }
                switch await attempt(url, client: client, parse: {
                    try StatuspalParser.parse(data: $0, sourceURL: base)
                }) {
                case .hit(let snapshot):
                    return snapshot
                case .miss:
                    sawHTTP = true
                case .networkError:
                    sawNetworkError = true
                }
            }
        }
        return nil
    }

    static func extractStatuspalSubdomain(from html: String) -> String? {
        let pattern = "statuspal\\.(?:io|eu)/api/v2/status_pages/([A-Za-z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let inner = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[inner])
    }
}
