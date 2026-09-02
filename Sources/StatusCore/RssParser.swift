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
            return try parseAtom(root, sourceURL: sourceURL)
        default:
            throw ParserError.notThisProvider
        }
    }

    private static func parseRSS(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        guard let channel = child(root, "channel") else {
            throw ParserError.notThisProvider
        }
        let components = children(channel, "item").compactMap(component(fromRSSItem:))
        return snapshot(
            name: text(channel, "title"),
            link: text(channel, "link"),
            sourceURL: sourceURL,
            components: components
        )
    }

    private static func parseAtom(_ root: XMLElement, sourceURL: URL) throws -> PageSnapshot {
        let components = children(root, "entry").compactMap(component(fromAtomEntry:))
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
        let pageURL = link.flatMap(httpURL) ?? sourceURL
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

    private static func component(fromRSSItem item: XMLElement) -> ComponentStatus? {
        let title = text(item, "title")
        let guid = text(item, "guid")
        let name = title ?? guid
        guard let name else { return nil }
        let raw = text(item, "status")
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw),
            statusText: StatusMapping.rssText(raw),
            id: guid ?? name
        )
    }

    private static func component(fromAtomEntry entry: XMLElement) -> ComponentStatus? {
        let title = text(entry, "title")
        let entryID = text(entry, "id")
        let name = title ?? entryID
        guard let name else { return nil }
        let raw = text(entry, "status")
        return ComponentStatus(
            name: name,
            severity: StatusMapping.rss(raw),
            statusText: StatusMapping.rssText(raw),
            id: entryID ?? name
        )
    }

    private static func atomLink(_ element: XMLElement) -> String? {
        let links = children(element, "link")
        let alternate = links.first { link in
            (link.attribute(forName: "rel")?.stringValue ?? "alternate") == "alternate"
        }
        let chosen = alternate ?? links.first
        if let href = chosen?.attribute(forName: "href")?.stringValue, !href.isEmpty {
            return href
        }
        return chosen.flatMap { textValue($0) }
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
