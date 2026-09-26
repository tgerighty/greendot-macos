import Foundation

extension ProviderProbe {
    static func probeRSS(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        if isMicrosoftLanding(context.base) {
            return try await probeMicrosoftHub(context: context, flags: &flags)
        }
        if isAzureStatusLanding(context.base) || isAzureStatusLanding(context.pageURL) {
            return try await fetchFeed(azureHubFeed, context: context, flags: &flags)
        }
        do {
            let located = try await context.client.getLocated(context.pageURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: located.status)
            guard located.status == 200 else { return nil }
            guard RedirectPolicy.allows(located.url, from: context.pageURL) else {
                return nil
            }
            if looksLikeFeed(located.data),
               let hit = feedHit(located.data, sourceURL: located.url, context: context) {
                return hit
            }
            guard let html = decodedText(located.data) else { return nil }
            let cleaned = htmlWithoutIgnoredMarkup(html)
            let page = located.url
            let base = documentBase(from: cleaned, fallback: page)
            guard let feedURL = extractAlternateFeedURL(from: cleaned, base: base, page: page) else {
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
        let prefix = decodedPrefix(data, maxBytes: 1024)?.lowercased() ?? ""
        let options: String.CompareOptions = .regularExpression
        return prefix.range(of: "<([a-zA-Z_][\\w.-]*:)?(rss|feed)(\\s|>|/)", options: options) != nil
    }

    static func decodedPrefix(_ data: Data, maxBytes: Int) -> String? {
        let slice = Data(data.prefix(maxBytes))
        if let text = decodeUTF16Bytes(slice) { return text }
        if let utf8 = String(data: slice, encoding: .utf8) { return utf8 }
        var trimmed = slice
        for _ in 0..<3 where !trimmed.isEmpty {
            trimmed.removeLast()
            if let utf8 = String(data: trimmed, encoding: .utf8) { return utf8 }
        }
        return String(data: slice, encoding: .isoLatin1)
    }

    static func decodedText(_ data: Data) -> String? {
        if let text = decodeUTF16Bytes(data) { return text }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    static func decodeUTF16Bytes(_ data: Data) -> String? {
        guard let encoding = UTF16Sniff.encoding(of: data, asciiLead: 0x3C) else { return nil }
        return String(data: data, encoding: encoding)
    }

    static func documentBase(from html: String, fallback: URL) -> URL {
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<" else {
                index = html.index(after: index)
                continue
            }
            if isBaseKeyword(html, from: index), let end = quotedTagEnd(html, from: index) {
                let href = linkAttribute(html[index...end], "href") ?? ""
                if !href.isEmpty,
                   let url = URL(string: decodeHTMLEntities(href), relativeTo: fallback)?.absoluteURL,
                   isAllowedFeedURL(url, relativeTo: fallback) {
                    return url
                }
                index = html.index(after: end)
                continue
            }
            index = html.index(after: index)
        }
        return fallback
    }

    static func extractAlternateFeedURL(from html: String, base: URL, page: URL) -> URL? {
        for tag in linkTags(in: html) {
            let rel = linkAttribute(tag, "rel")?.lowercased() ?? ""
            guard relationTokens(rel).contains("alternate") else { continue }
            let type = linkAttribute(tag, "type") ?? ""
            guard isFeedLinkType(type) else { continue }
            guard let href = linkAttribute(tag, "href"), !href.isEmpty else { continue }
            let decoded = decodeHTMLEntities(href)
            if let url = URL(string: decoded, relativeTo: base)?.absoluteURL,
               isAllowedFeedURL(url, relativeTo: page) {
                return url
            }
        }
        return nil
    }

    static func isAzureStatusLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "azure.status.microsoft" || host == "status.azure.com"
    }

    static func isMicrosoftLanding(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "status.cloud.microsoft" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        CFXMLCreateStringByUnescapingEntities(nil, value as CFString, nil) as String? ?? value
    }

    static func isAllowedFeedURL(_ url: URL, relativeTo base: URL) -> Bool {
        RedirectPolicy.allows(url, from: base)
    }

    static func relationTokens(_ rel: String) -> [String] {
        rel.split { $0.isWhitespace || $0 == "," }.map(String.init)
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

    static func fetchFeed(
        _ feedURL: URL,
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        do {
            let located = try await context.client.getLocated(feedURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: located.status)
            guard RedirectPolicy.allows(located.url, from: feedURL) else {
                return nil
            }
            guard located.status == 200, looksLikeFeed(located.data) else { return nil }
            return feedHit(located.data, sourceURL: located.url, context: context)
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
        if let hit = context.cachedHit(for: body) { return hit }
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
        let body = feedCacheBody(data, sourceURL: sourceURL)
        if let hit = context.cachedHit(for: body) { return hit }
        do {
            recordParse()
            let snapshot = try RssParser.parse(data: data, sourceURL: sourceURL)
            return ProbeHit(snapshot: snapshot, body: body)
        } catch {
            return nil
        }
    }

    static func feedCacheBody(_ data: Data, sourceURL: URL) -> Data {
        var body = Data(sourceURL.absoluteString.utf8)
        body.append(0)
        body.append(data)
        return body
    }

    static func linkAttribute(_ tag: Substring, _ name: String) -> String? {
        attributes(in: String(tag))[name.lowercased()]
    }

    private static let attributeRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-\w:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        )
    }()

    static func attributes(in tag: String) -> [String: String] {
        guard let regex = attributeRegex else { return [:] }
        let start = tag.firstIndex { $0.isWhitespace || $0 == ">" } ?? tag.endIndex
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(start..<tag.endIndex, in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag),
                  let value = (2...4).compactMap({ Range(match.range(at: $0), in: tag) }).first
            else { continue }
            result[tag[name].lowercased()] = String(tag[value])
        }
        return result
    }
}
