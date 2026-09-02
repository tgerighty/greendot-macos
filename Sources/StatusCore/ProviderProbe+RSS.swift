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
            let located = try await context.client.getLocated(context.pageURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: located.status)
            guard located.status == 200 else { return nil }
            guard RedirectPolicy.allows(URLRequest(url: located.url), from: context.pageURL) else {
                return nil
            }
            if looksLikeFeed(located.data),
               let hit = feedHit(located.data, sourceURL: located.url, context: context) {
                return hit
            }
            guard let html = decodedText(located.data),
                  let feedURL = extractAlternateFeedURL(
                    from: htmlWithoutIgnoredMarkup(html),
                    base: located.url
                  ) else {
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

    static func decodedText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    static func decodedPrefix(_ data: Data, maxBytes: Int) -> String? {
        let slice = Data(data.prefix(maxBytes))
        if let utf8 = String(data: slice, encoding: .utf8) { return utf8 }
        var trimmed = slice
        for _ in 0..<3 where !trimmed.isEmpty {
            trimmed.removeLast()
            if let utf8 = String(data: trimmed, encoding: .utf8) { return utf8 }
        }
        return String(data: slice, encoding: .utf16)
    }

    static func extractAlternateFeedURL(from html: String, base: URL) -> URL? {
        for tag in linkTags(in: html) {
            let rel = linkAttribute(tag, "rel")?.lowercased() ?? ""
            guard relationTokens(rel).contains("alternate") else { continue }
            let type = linkAttribute(tag, "type") ?? ""
            guard isFeedLinkType(type) else { continue }
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
        CFXMLCreateStringByUnescapingEntities(nil, value as CFString, nil) as String? ?? value
    }

    static func isAllowedFeedURL(_ url: URL, relativeTo base: URL) -> Bool {
        RedirectPolicy.allows(URLRequest(url: url), from: base)
    }

    static func relationTokens(_ rel: String) -> [String] {
        rel.split { $0.isWhitespace || $0 == "," }.map(String.init)
    }

    static func linkTags(in html: String) -> [Substring] {
        var tags: [Substring] = []
        var index = html.startIndex
        while index < html.endIndex {
            guard let start = linkTagStart(html, from: index) else { break }
            if let end = quotedTagEnd(html, from: start) {
                tags.append(html[start...end])
                index = html.index(after: end)
            } else {
                index = html.index(after: start)
            }
        }
        return tags
    }

    static func linkTagStart(_ html: String, from: String.Index) -> String.Index? {
        var index = from
        while index < html.endIndex {
            if html[index] == "<", isLinkKeyword(html, from: index) {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    static func isLinkKeyword(_ html: String, from: String.Index) -> Bool {
        var index = from
        for expected in "<link" {
            guard index < html.endIndex else { return false }
            guard html[index].lowercased() == String(expected) else { return false }
            index = html.index(after: index)
        }
        guard index < html.endIndex else { return false }
        return html[index].isWhitespace
    }

    static func quotedTagEnd(_ html: String, from: String.Index) -> String.Index? {
        var quote: Character?
        var index = from
        while index < html.endIndex {
            let character = html[index]
            if let current = quote {
                if character == current { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    static func isFeedLinkType(_ type: String) -> Bool {
        let essence = type.split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return essence == "application/rss+xml" || essence == "application/atom+xml"
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

    static let htmlIgnoredMarkupRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(
            pattern: "<!--.*?-->"
                + "|<script\\b[^>]*>.*?</script\\s*>"
                + "|<style\\b[^>]*>.*?</style\\s*>"
                + "|<template\\b[^>]*>.*?</template\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    static func htmlWithoutIgnoredMarkup(_ html: String) -> String {
        guard let regex = htmlIgnoredMarkupRegex else { return html }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.stringByReplacingMatches(in: html, options: [], range: range, withTemplate: "")
    }

    static func fetchFeed(
        _ feedURL: URL,
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        do {
            let located = try await context.client.getLocated(feedURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: located.status)
            guard RedirectPolicy.allows(URLRequest(url: located.url), from: feedURL) else {
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
        let body = feedCacheBody(data, sourceURL: sourceURL)
        if let previousBody = context.previousBody,
           let previousSnapshot = context.previousSnapshot,
           !previousSnapshot.isUnreachable,
           body == previousBody {
            return ProbeHit(snapshot: previousSnapshot, body: body)
        }
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

    static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        let chars = Array(tag)
        var index = skipToken(chars, from: 0)
        while index < chars.count {
            index = skipSpaces(chars, from: index)
            guard index < chars.count, chars[index] != ">" else { break }
            let (key, afterName) = readToken(chars, from: index)
            index = skipSpaces(chars, from: afterName)
            guard index < chars.count, chars[index] == "=" else { continue }
            let (value, afterValue) = readAttributeValue(chars, from: skipSpaces(chars, from: index + 1))
            index = afterValue
            if !key.isEmpty { result[key.lowercased()] = value }
        }
        return result
    }

    static func skipSpaces(_ chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count, chars[index].isWhitespace { index += 1 }
        return index
    }

    static func skipToken(_ chars: [Character], from start: Int) -> Int {
        var index = start
        while index < chars.count, !chars[index].isWhitespace, chars[index] != ">" { index += 1 }
        return index
    }

    static func readToken(_ chars: [Character], from start: Int) -> (String, Int) {
        var index = start
        while index < chars.count,
              chars[index] != "=",
              !chars[index].isWhitespace,
              chars[index] != ">" {
            index += 1
        }
        return (String(chars[start..<index]), index)
    }

    static func readAttributeValue(_ chars: [Character], from start: Int) -> (String, Int) {
        guard start < chars.count else { return ("", start) }
        if chars[start] == "\"" || chars[start] == "'" {
            let quote = chars[start]
            var index = start + 1
            while index < chars.count, chars[index] != quote { index += 1 }
            let value = String(chars[(start + 1)..<index])
            if index < chars.count { index += 1 }
            return (value, index)
        }
        var index = start
        while index < chars.count, !chars[index].isWhitespace, chars[index] != ">" { index += 1 }
        return (String(chars[start..<index]), index)
    }
}
