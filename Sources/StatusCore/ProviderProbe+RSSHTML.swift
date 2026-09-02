import Foundation

extension ProviderProbe {
    static func linkTags(in html: String) -> [Substring] {
        var tags: [Substring] = []
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<" else {
                index = html.index(after: index)
                continue
            }
            if isLinkKeyword(html, from: index) {
                if let end = quotedTagEnd(html, from: index) {
                    tags.append(html[index...end])
                    index = html.index(after: end)
                } else {
                    index = html.index(after: index)
                }
                continue
            }
            if let end = quotedTagEnd(html, from: index) {
                index = html.index(after: end)
            } else {
                index = html.index(after: index)
            }
        }
        return tags
    }

    static func isFeedLinkType(_ type: String) -> Bool {
        let essence = type.split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return essence == "application/rss+xml" || essence == "application/atom+xml"
    }
}

extension ProviderProbe {
    static let htmlIgnoredMarkupRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(
            pattern: "<!--.*?-->"
                + "|<script\\b[^>]*>.*?</script\\s*>"
                + "|<style\\b[^>]*>.*?</style\\s*>"
                + "|<textarea\\b[^>]*>.*?</textarea\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    static let innermostTemplateRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(
            pattern: "<template\\b[^>]*>(?:(?!<template\\b).)*?</template\\s*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    static func htmlWithoutIgnoredMarkup(_ html: String) -> String {
        var current = stripRepeating(innermostTemplateRegex, in: html)
        return stripRepeating(htmlIgnoredMarkupRegex, in: current)
    }

    static func stripRepeating(_ regex: NSRegularExpression?, in html: String) -> String {
        guard let regex else { return html }
        var current = html
        for _ in 0..<64 {
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            let next = regex.stringByReplacingMatches(in: current, options: [], range: range, withTemplate: "")
            if next == current { return current }
            current = next
        }
        return current
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
}
