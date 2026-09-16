import Foundation
import os

public enum ProbeError: Error, Equatable, LocalizedError {
    case unsupported
    case unreachable
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This URL is not a known status page format "
                + "(Statuspage, Statuspal, Instatus, Flashduty, AWS, Icinga, Okta, Salesforce, Status.io, Slack, Heroku, Google, Apple, incident.io, or RSS/Atom)."
        case .unreachable:
            return "Could not reach that URL."
        case .unauthorized:
            return "That URL requires a username and password in the URL (https://user:password@host/...)."
        }
    }
}

public enum ProviderProbe {
    static var parseCount: Int { parseBox.withLock { $0 } }
    static var regexCompileCount: Int { regexBox.withLock { $0 } }

    static func resetCounts() {
        parseBox.withLock { $0 = 0 }
        regexBox.withLock { $0 = 0 }
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
        let context = ProbeContext(
            base: normalizedBase(pageURL),
            pageURL: pageURL,
            client: client,
            previousBody: previousBody,
            previousSnapshot: previousSnapshot
        )
        var flags = ProbeFlags()
        if let hit = try await probeAWSIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeIcingaIfAPI(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeOktaIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeSalesforceIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeSlackIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeHerokuIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeGoogleIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeAppleIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeStripeIfLanding(context: context, flags: &flags) {
            return hit
        }
        for provider in probeOrder(preferring: prefer) {
            switch provider {
            case .statuspage, .instatus, .flashduty:
                if let hit = flags.record(try await standardAttempt(for: provider, context: context)) {
                    return hit
                }
            case .statuspal:
                if let hit = try await probeStatuspal(context: context, flags: &flags) { return hit }
            case .statusio:
                if let hit = try await probeStatusio(context: context, flags: &flags) { return hit }
            case .incidentio:
                if let hit = try await probeIncidentio(context: context, flags: &flags) { return hit }
            case .aws, .icinga, .okta, .salesforce, .slack, .heroku, .google, .apple:
                continue
            case .rss:
                if let hit = try await probeRSS(context: context, flags: &flags) { return hit }
            }
        }
        throw flags.finalError
    }

    static func probeOrder(preferring prefer: StatusProvider?) -> [StatusProvider] {
        let order: [StatusProvider] = [
            .statuspage, .instatus, .flashduty, .statuspal, .statusio, .incidentio,
            .aws, .icinga, .okta, .salesforce, .slack, .heroku, .google, .apple, .rss
        ]
        guard let prefer, prefer != .statuspage else { return order }
        return [prefer] + order.filter { $0 != prefer }
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

    /// URL stored on a watched page. Keeps query and path, including a trailing slash.
    public static func persistedPageURL(_ url: URL) -> URL {
        var text = url.absoluteString
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.scheme == nil {
            text = "https://" + text
        }
        var parts = URLComponents(string: text) ?? URLComponents()
        parts.fragment = nil
        return parts.url ?? url
    }

    enum AttemptResult {
        case hit(ProbeHit)
        case miss
        case networkError
    }

    struct ProbeContext: Sendable {
        let base: URL
        let pageURL: URL
        let client: HTTPClient
        let previousBody: Data?
        let previousSnapshot: PageSnapshot?
    }

    struct ProbeFlags {
        var sawNetworkError = false

        mutating func recordHTTP(status: Int) {
            if ProviderProbe.isReachabilityStatus(status) {
                sawNetworkError = true
            }
        }

        mutating func record(_ result: AttemptResult) -> ProbeHit? {
            switch result {
            case .hit(let hit):
                return hit
            case .miss:
                return nil
            case .networkError:
                sawNetworkError = true
                return nil
            }
        }

        var finalError: ProbeError {
            sawNetworkError ? .unreachable : .unsupported
        }
    }

    static func isReachabilityStatus(_ status: Int) -> Bool {
        status == 0 || status == 429 || (500...599).contains(status)
    }

    private static func standardAttempt(
        for provider: StatusProvider,
        context: ProbeContext
    ) async throws -> AttemptResult {
        let endpoint: URL
        let parse: (Data) throws -> PageSnapshot
        switch provider {
        case .statuspage:
            endpoint = context.base.appendingPathComponent("api/v2/summary.json")
            parse = { try StatuspageParser.parse(data: $0, sourceURL: context.base) }
        case .instatus:
            endpoint = context.base.appendingPathComponent("summary.json")
            parse = { try InstatusParser.parse(data: $0, sourceURL: context.base) }
        case .flashduty:
            endpoint = context.base.appendingPathComponent("api/widget/v1/summary.json")
            parse = { try FlashdutyParser.parse(data: $0, sourceURL: context.base) }
        case .statuspal, .rss, .aws, .icinga, .okta, .salesforce,
             .statusio, .slack, .heroku, .google, .apple, .incidentio:
            // unreachable: routed elsewhere
            return .miss
        }
        return try await attempt(
            endpoint,
            client: context.client,
            previousBody: context.previousBody,
            previousSnapshot: context.previousSnapshot,
            parse: parse
        )
    }

    static func attempt(
        _ url: URL,
        client: HTTPClient,
        previousBody: Data?,
        previousSnapshot: PageSnapshot?,
        parse: (Data) throws -> PageSnapshot
    ) async throws -> AttemptResult {
        do {
            let (data, status) = try await client.get(url)
            try Task.checkCancellation()
            guard status == 200 else {
                return isReachabilityStatus(status) ? .networkError : .miss
            }
            if let previousBody, let previousSnapshot,
               !previousSnapshot.isUnreachable,
               data == previousBody {
                return .hit(ProbeHit(snapshot: previousSnapshot, body: data))
            }
            do {
                parseBox.withLock { $0 += 1 }
                return .hit(ProbeHit(snapshot: try parse(data), body: data))
            } catch {
                return .miss
            }
        } catch {
            try throwIfCancelled(error)
            return .networkError
        }
    }

    private static func probeStatuspal(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        let host = context.base.host ?? ""
        var subdomains: [String] = []
        if host.hasSuffix(".statuspal.io") || host.hasSuffix(".statuspal.eu") {
            subdomains.append(host.split(separator: ".").first.map(String.init) ?? host)
        }
        if subdomains.isEmpty {
            do {
                let htmlHit = try await context.client.get(context.base)
                try Task.checkCancellation()
                flags.recordHTTP(status: htmlHit.1)
                if htmlHit.1 == 200,
                   let html = String(data: htmlHit.0, encoding: .utf8),
                   html.lowercased().contains("statuspal"),
                   let extracted = extractStatuspalSubdomain(from: html) {
                    subdomains.append(extracted)
                }
            } catch {
                try throwIfCancelled(error)
                flags.sawNetworkError = true
            }
        }
        let unique = Array(NSOrderedSet(array: subdomains)) as? [String] ?? subdomains
        let apiHosts = ["https://statuspal.io/api/v2/status_pages/", "https://statuspal.eu/api/v2/status_pages/"]
        for subdomain in unique {
            for prefix in apiHosts {
                guard let url = URL(string: prefix + subdomain + "/summary") else { continue }
                if let hit = flags.record(try await attempt(
                    url,
                    client: context.client,
                    previousBody: context.previousBody,
                    previousSnapshot: context.previousSnapshot,
                    parse: { try StatuspalParser.parse(data: $0, sourceURL: context.base) }
                )) { return hit }
            }
        }
        return nil
    }

    static func throwIfCancelled(_ error: Error) throws {
        guard !(error is CancellationError || Task.isCancelled) else {
            throw CancellationError()
        }
    }

    private static let statuspalRegex: NSRegularExpression? = {
        regexBox.withLock { $0 += 1 }
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

private let parseBox = OSAllocatedUnfairLock(initialState: 0)
private let regexBox = OSAllocatedUnfairLock(initialState: 0)

extension ProviderProbe {
    static func recordParse() {
        parseBox.withLock { $0 += 1 }
    }

    static func recordRegex() {
        regexBox.withLock { $0 += 1 }
    }
}
