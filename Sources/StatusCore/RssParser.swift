import Foundation

public enum RssParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        let document: XMLDocument
        do {
            if let text = utf16XMLString(data) {
                document = try XMLDocument(
                    xmlString: utf8XMLDeclaration(text),
                    options: [.nodeLoadExternalEntitiesNever]
                )
            } else {
                document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
            }
        } catch {
            throw ParserError.notThisProvider
        }
        guard let root = document.rootElement() else {
            throw ParserError.notThisProvider
        }
        switch localName(root) {
        case "rss":
            guard (root.uri ?? "").isEmpty else {
                throw ParserError.notThisProvider
            }
            return try parseRSS(root, sourceURL: sourceURL)
        case "feed":
            guard root.uri == "http://www.w3.org/2005/Atom" else {
                throw ParserError.notThisProvider
            }
            return try parseAtom(root, sourceURL: sourceURL)
        default:
            throw ParserError.notThisProvider
        }
    }

    private static let rssNamespace = ""
    private static let atomNamespace = "http://www.w3.org/2005/Atom"

    private static func utf16XMLString(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(2))
        let encoding: String.Encoding
        if bytes[0] == 0, bytes[1] == 0x3C {
            encoding = .utf16BigEndian
        } else if bytes[0] == 0x3C, bytes[1] == 0 {
            encoding = .utf16LittleEndian
        } else {
            return nil
        }
        return String(data: data, encoding: encoding)
    }

    private static func utf8XMLDeclaration(_ text: String) -> String {
        guard let end = text.range(of: "?>") else { return text }
        let declaration = text[..<end.upperBound]
        let rewritten = declaration.replacingOccurrences(
            of: #"encoding\s*=\s*["']utf-16(?:le|be)?["']"#,
            with: "encoding=\"utf-8\"",
            options: [.regularExpression, .caseInsensitive]
        )
        return rewritten + text[end.upperBound...]
    }

    private static func parseRSS(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        guard let channel = child(root, "channel", uri: rssNamespace) else {
            throw ParserError.notThisProvider
        }
        let missing = missingSeverity(for: sourceURL)
        let components = children(channel, "item", uri: rssNamespace).compactMap {
            component(fromRSSItem: $0, missing: missing)
        }
        return snapshot(
            name: text(channel, "title", uri: rssNamespace),
            link: text(channel, "link", uri: rssNamespace),
            sourceURL: sourceURL,
            base: sourceURL,
            components: components
        )
    }

    private static func parseAtom(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        let missing = missingSeverity(for: sourceURL)
        let components = children(root, "entry", uri: atomNamespace).compactMap {
            component(fromAtomEntry: $0, missing: missing)
        }
        return snapshot(
            name: text(root, "title", uri: atomNamespace),
            link: atomLink(root, fallback: sourceURL),
            sourceURL: sourceURL,
            base: xmlBase(root, fallback: sourceURL),
            components: components
        )
    }

    private static func snapshot(
        name: String?,
        link: String?,
        sourceURL: URL,
        base: URL,
        components: [ComponentStatus]
    ) -> PageSnapshot {
        let pageURL = resolvedPageURL(link, sourceURL: sourceURL, base: base)
        let pageName = name.flatMap { $0.isEmpty ? nil : $0 } ?? sourceURL.host ?? "Status page"
        return PageSnapshot(
            name: pageName,
            url: pageURL,
            provider: .rss,
            overall: ComponentTree.enabledLeafSeverity(in: components, disabledKeys: []),
            components: components,
            incidents: [],
            isUnreachable: false
        )
    }

    private static func missingSeverity(for url: URL) -> Severity {
        isAzureStatusHost(url.host) || isAWSStatusHost(url.host) ? .yellow : .green
    }

    private static func isAzureStatusHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "azure.status.microsoft" || host.hasSuffix(".azure.status.microsoft")
    }

    private static func isAWSStatusHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "status.aws.amazon.com" || host.hasSuffix(".status.aws.amazon.com")
    }

    private static func component(fromRSSItem item: XMLElement, missing: Severity) -> ComponentStatus? {
        let title = text(item, "title", uri: rssNamespace)
        let guid = text(item, "guid", uri: rssNamespace)
        let name = title ?? guid ?? text(item, "description", uri: rssNamespace)
        guard let name else { return nil }
        let raw = itemStatus(item, uri: rssNamespace)
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw, missing: missing),
            statusText: StatusMapping.rssText(raw, missing: missing),
            id: guid ?? name
        )
    }

    private static func component(fromAtomEntry entry: XMLElement, missing: Severity) -> ComponentStatus? {
        let title = text(entry, "title", uri: atomNamespace)
        let entryID = text(entry, "id", uri: atomNamespace)
        let name = title ?? entryID
        guard let name else { return nil }
        let raw = itemStatus(entry, uri: atomNamespace)
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw, missing: missing),
            statusText: StatusMapping.rssText(raw, missing: missing),
            id: entryID ?? name
        )
    }

    private static func atomLink(_ element: XMLElement, fallback: URL) -> String? {
        let feedBase = xmlBase(element, fallback: fallback)
        let links = children(element, "link", uri: atomNamespace)
        let chosen = links.first { atomLinkRelation($0) == "alternate" }
            ?? links.first { atomLinkRelation($0) == "self" }
        let href = chosen?.attribute(forName: "href")?.stringValue
        let raw = (href?.isEmpty == false ? href : nil) ?? chosen.flatMap { textValue($0) }
        guard let raw else { return nil }
        let base = chosen.map { xmlBase($0, fallback: feedBase) } ?? feedBase
        return resolvedPageURL(raw, sourceURL: fallback, base: base).absoluteString
    }

    private static func atomLinkRelation(_ link: XMLElement) -> String {
        (link.attribute(forName: "rel")?.stringValue ?? "alternate").lowercased()
    }

    private static func xmlBase(_ element: XMLElement, fallback: URL) -> URL {
        let raw = element.attribute(
            forLocalName: "base",
            uri: "http://www.w3.org/XML/1998/namespace"
        )?.stringValue ?? element.attribute(forName: "xml:base")?.stringValue
        guard let raw, !raw.isEmpty else { return fallback }
        if let url = URL(string: raw, relativeTo: fallback)?.absoluteURL,
           httpURL(url.absoluteString) != nil {
            return url
        }
        return fallback
    }

    private static func resolvedPageURL(_ link: String?, sourceURL: URL, base: URL) -> URL {
        guard let link, !link.isEmpty else { return sourceURL }
        if let absolute = httpURL(link) { return absolute }
        if let resolved = URL(string: link, relativeTo: base)?.absoluteURL,
           httpURL(resolved.absoluteString) != nil {
            return resolved
        }
        return sourceURL
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private static func itemStatus(_ element: XMLElement, uri: String) -> String? {
        text(element, "status", uri: uri)
            ?? knownCategory(element, uri: uri)
            ?? descriptionStatus(text(element, "description", uri: uri))
    }

    private static func descriptionStatus(_ description: String?) -> String? {
        guard let description else { return nil }
        if let status = labeledValue(description, "status"), status.lowercased() == "resolved" {
            return status
        }
        return labeledValue(description, "severity").flatMap(StatusMapping.rssKnownToken)
    }

    private static func labeledValue(_ text: String, _ label: String) -> String? {
        let haystack = text.lowercased()
        let needle = label.lowercased() + ":"
        guard let start = haystack.range(of: needle) else { return nil }
        let rest = haystack[start.upperBound...].drop { $0.isWhitespace }
        let token = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return token.isEmpty ? nil : String(token)
    }

    private static func knownCategory(_ element: XMLElement, uri: String) -> String? {
        let tokens = children(element, "category", uri: uri).compactMap { node -> String? in
            let raw = node.attribute(forName: "term")?.stringValue ?? textValue(node)
            return raw.flatMap(StatusMapping.rssKnownToken)
        }
        guard !tokens.isEmpty else { return nil }
        let worst = Aggregator.fromSeverities(tokens.map { StatusMapping.rss($0) })
        return tokens.first { StatusMapping.rss($0) == worst }
    }

    private static func text(_ element: XMLElement, _ name: String, uri: String) -> String? {
        child(element, name, uri: uri).flatMap(textValue)
    }

    private static func textValue(_ element: XMLElement) -> String? {
        let value = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func child(_ element: XMLElement, _ name: String, uri: String) -> XMLElement? {
        children(element, name, uri: uri).first
    }

    private static func children(_ element: XMLElement, _ name: String, uri: String) -> [XMLElement] {
        element.children?.compactMap { node -> XMLElement? in
            guard let child = node as? XMLElement, localName(child) == name else { return nil }
            guard (child.uri ?? "") == uri else { return nil }
            return child
        } ?? []
    }

    private static func localName(_ element: XMLElement) -> String {
        element.localName ?? element.name ?? ""
    }
}
