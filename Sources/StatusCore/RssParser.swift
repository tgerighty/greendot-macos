import Foundation

public enum RssParser {
    public static func parse(data: Data, sourceURL: URL) throws -> PageSnapshot {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw ParserError.notThisProvider
        }
        guard let root = document.rootElement() else {
            throw ParserError.notThisProvider
        }
        switch localName(root) {
        case "rss":
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

    private static func parseRSS(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        guard let channel = child(root, "channel") else {
            throw ParserError.notThisProvider
        }
        let missing = missingSeverity(for: sourceURL)
        let components = children(channel, "item").compactMap {
            component(fromRSSItem: $0, missing: missing)
        }
        return snapshot(
            name: text(channel, "title"),
            link: text(channel, "link"),
            sourceURL: sourceURL,
            components: components
        )
    }

    private static func parseAtom(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        let missing = missingSeverity(for: sourceURL)
        let components = children(root, "entry").compactMap {
            component(fromAtomEntry: $0, missing: missing)
        }
        return snapshot(
            name: text(root, "title"),
            link: atomLink(root),
            sourceURL: sourceURL,
            components: components
        )
    }

    private static func snapshot(
        name: String?,
        link: String?,
        sourceURL: URL,
        components: [ComponentStatus]
    ) -> PageSnapshot {
        let pageURL = resolvedPageURL(link, sourceURL: sourceURL)
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
        isAzureStatusHost(url.host) ? .yellow : .green
    }

    private static func isAzureStatusHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "azure.status.microsoft" || host.hasSuffix(".azure.status.microsoft")
    }

    private static func component(fromRSSItem item: XMLElement, missing: Severity) -> ComponentStatus? {
        let title = text(item, "title")
        let guid = text(item, "guid")
        let name = title ?? guid
        guard let name else { return nil }
        let raw = text(item, "status")
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw, missing: missing),
            statusText: StatusMapping.rssText(raw, missing: missing),
            id: guid ?? name
        )
    }

    private static func component(fromAtomEntry entry: XMLElement, missing: Severity) -> ComponentStatus? {
        let title = text(entry, "title")
        let entryID = text(entry, "id")
        let name = title ?? entryID
        guard let name else { return nil }
        let raw = text(entry, "status")
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw, missing: missing),
            statusText: StatusMapping.rssText(raw, missing: missing),
            id: entryID ?? name
        )
    }

    private static func atomLink(_ element: XMLElement) -> String? {
        let links = children(element, "link")
        let chosen = links.first { atomLinkRelation($0) == "alternate" }
            ?? links.first { atomLinkRelation($0) == "self" }
        if let href = chosen?.attribute(forName: "href")?.stringValue, !href.isEmpty {
            return href
        }
        return chosen.flatMap { textValue($0) }
    }

    private static func atomLinkRelation(_ link: XMLElement) -> String {
        (link.attribute(forName: "rel")?.stringValue ?? "alternate").lowercased()
    }

    private static func resolvedPageURL(_ link: String?, sourceURL: URL) -> URL {
        guard let link, !link.isEmpty else { return sourceURL }
        if let absolute = httpURL(link) { return absolute }
        if let resolved = URL(string: link, relativeTo: sourceURL)?.absoluteURL,
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

    private static func text(_ element: XMLElement, _ name: String) -> String? {
        child(element, name).flatMap(textValue)
    }

    private static func textValue(_ element: XMLElement) -> String? {
        let value = element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func child(_ element: XMLElement, _ name: String) -> XMLElement? {
        children(element, name).first
    }

    private static func children(_ element: XMLElement, _ name: String) -> [XMLElement] {
        element.children?.compactMap { node -> XMLElement? in
            guard let child = node as? XMLElement, localName(child) == name else { return nil }
            return child
        } ?? []
    }

    private static func localName(_ element: XMLElement) -> String {
        element.localName ?? element.name ?? ""
    }
}
