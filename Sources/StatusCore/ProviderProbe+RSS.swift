import Foundation

extension ProviderProbe {
    static func probeRSS(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        if isMicrosoftLanding(context.base) {
            return try await probeMicrosoftHub(context: context, flags: &flags)
        }
        do {
            let (data, status) = try await context.client.get(context.pageURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: status)
            guard status == 200 else { return nil }
            if looksLikeFeed(data) {
                return feedHit(data, sourceURL: context.pageURL, context: context)
            }
            guard let html = String(data: data, encoding: .utf8),
                  let feedURL = extractAlternateFeedURL(from: html, base: context.pageURL) else {
                return nil
            }
            return try await fetchFeed(feedURL, context: context, flags: &flags)
        } catch {
            try throwIfCancelled(error)
            flags.sawNetworkError = true
            return nil
        }
    }

    static func looksLikeFeed(_ data: Data) -> Bool {
        let prefix = String(data: data.prefix(512), encoding: .utf8)?.lowercased() ?? ""
        let options: String.CompareOptions = .regularExpression
        return prefix.range(of: "<rss(\\s|>|/)", options: options) != nil
            || prefix.range(of: "<feed(\\s|>|/)", options: options) != nil
    }

    static func extractAlternateFeedURL(from html: String, base: URL) -> URL? {
        guard let regex = alternateLinkRegex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = html[tagRange]
            let rel = linkAttribute(tag, "rel")?.lowercased() ?? ""
            guard rel.contains("alternate") else { continue }
            let type = linkAttribute(tag, "type")?.lowercased() ?? ""
            guard type.contains("rss+xml") || type.contains("atom+xml") else { continue }
            guard let href = linkAttribute(tag, "href"), !href.isEmpty else { continue }
            let decoded = decodeHTMLEntities(href)
            if let url = URL(string: decoded, relativeTo: base)?.absoluteURL,
               isAllowedFeedURL(url, relativeTo: base) {
                return url
            }
        }
        return nil
    }

    static func isMicrosoftLanding(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "status.cloud.microsoft" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    static func isAllowedFeedURL(_ url: URL, relativeTo base: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let feedHost = url.host?.lowercased(), let baseHost = base.host?.lowercased() else {
            return false
        }
        return feedHost == baseHost
    }
}

private struct RSSHubFeed {
    let id: String
    let name: String
    let url: URL
}

private extension ProviderProbe {
    static let azureHubFeed = URL(string: "https://rssfeed.azure.status.microsoft/en-us/status/feed/")!
    static let feedSeparator = Data("\n<!--greendot-rss-feed-->\n".utf8)

    static let alternateLinkRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(pattern: "<link\\s[^>]*>", options: [.caseInsensitive])
    }()

    static func fetchFeed(
        _ feedURL: URL,
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        do {
            let (data, status) = try await context.client.get(feedURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: status)
            guard status == 200, looksLikeFeed(data) else { return nil }
            return feedHit(data, sourceURL: feedURL, context: context)
        } catch {
            try throwIfCancelled(error)
            flags.sawNetworkError = true
            return nil
        }
    }

    static func probeMicrosoftHub(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        let feeds = microsoftHubFeeds(base: context.base)
        var parts: [Data] = []
        var statuses: [Int] = []
        for feed in feeds {
            do {
                let (data, status) = try await context.client.get(feed.url)
                try Task.checkCancellation()
                flags.recordHTTP(status: status)
                parts.append(data)
                statuses.append(status)
            } catch {
                try throwIfCancelled(error)
                flags.sawNetworkError = true
                parts.append(Data())
                statuses.append(0)
            }
        }
        let body = hubCacheBody(parts: parts, statuses: statuses)
        if let previousBody = context.previousBody,
           let previousSnapshot = context.previousSnapshot,
           !previousSnapshot.isUnreachable,
           body == previousBody {
            return ProbeHit(snapshot: previousSnapshot, body: body)
        }
        var groups: [ComponentStatus] = []
        var parsedAny = false
        for (index, feed) in feeds.enumerated() {
            let status = index < statuses.count ? statuses[index] : 0
            groups.append(
                parseHubGroup(feed, data: parts[index], status: status, parsedAny: &parsedAny)
            )
        }
        guard parsedAny else { return nil }
        return ProbeHit(
            snapshot: PageSnapshot(
                name: "Microsoft",
                url: context.base,
                provider: .rss,
                overall: ComponentTree.enabledLeafSeverity(in: groups, disabledKeys: []),
                components: groups,
                incidents: [],
                isUnreachable: false
            ),
            body: body
        )
    }

    static func parseHubGroup(
        _ feed: RSSHubFeed,
        data: Data,
        status: Int,
        parsedAny: inout Bool
    ) -> ComponentStatus {
        guard status == 200, looksLikeFeed(data) else { return greyGroup(feed) }
        do {
            recordParse()
            let parsed = try RssParser.parse(data: data, sourceURL: feed.url)
            parsedAny = true
            let children = parsed.components
            let severity = ComponentTree.enabledLeafSeverity(in: children, disabledKeys: [])
            return ComponentStatus(
                name: feed.name,
                severity: severity,
                statusText: severity.displayName,
                id: feed.id,
                children: children,
                isGroup: true
            )
        } catch {
            return greyGroup(feed)
        }
    }

    static func greyGroup(_ feed: RSSHubFeed) -> ComponentStatus {
        ComponentStatus(
            name: feed.name,
            severity: .grey,
            statusText: Severity.grey.displayName,
            id: feed.id,
            children: [],
            isGroup: true
        )
    }

    static func microsoftHubFeeds(base: URL) -> [RSSHubFeed] {
        [
            RSSHubFeed(id: "m365", name: "Microsoft 365", url: pathURL(base, "/api/feed/mac")),
            RSSHubFeed(id: "ppac", name: "Power Platform", url: pathURL(base, "/api/feed/ppac")),
            RSSHubFeed(id: "azure", name: "Azure", url: azureHubFeed)
        ]
    }

    static func pathURL(_ base: URL, _ path: String) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = path
        return parts.url ?? base
    }

    static func hubCacheBody(parts: [Data], statuses: [Int]) -> Data {
        var body = Data()
        for (index, part) in parts.enumerated() {
            if index > 0 { body.append(feedSeparator) }
            let status = index < statuses.count ? statuses[index] : 0
            body.append(Data("HTTP \(status)\n".utf8))
            body.append(part)
        }
        return body
    }

    static func feedHit(_ data: Data, sourceURL: URL, context: ProbeContext) -> ProbeHit? {
        if let previousBody = context.previousBody,
           let previousSnapshot = context.previousSnapshot,
           !previousSnapshot.isUnreachable,
           data == previousBody {
            return ProbeHit(snapshot: previousSnapshot, body: data)
        }
        do {
            recordParse()
            let snapshot = try RssParser.parse(data: data, sourceURL: sourceURL)
            return ProbeHit(snapshot: snapshot, body: data)
        } catch {
            return nil
        }
    }

    static let attributeRegexByName: [String: NSRegularExpression] = {
        recordRegex()
        var compiled: [String: NSRegularExpression] = [:]
        for name in ["rel", "type", "href"] {
            if let regex = try? NSRegularExpression(
                pattern: "(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)'|([^\\s>]+))",
                options: [.caseInsensitive]
            ) {
                compiled[name] = regex
            }
        }
        return compiled
    }()

    static func linkAttribute(_ tag: Substring, _ name: String) -> String? {
        guard let regex = attributeRegexByName[name] else { return nil }
        let text = String(tag)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        for index in 1...3 {
            let captured = match.range(at: index)
            if captured.location != NSNotFound, let inner = Range(captured, in: text) {
                return String(text[inner])
            }
        }
        return nil
    }
}
