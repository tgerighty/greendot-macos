import Foundation

extension ProviderProbe {
    static func probeStatusio(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        let html: Data
        let htmlStatus: Int
        do {
            let hit = try await context.client.get(context.base)
            try Task.checkCancellation()
            flags.recordHTTP(status: hit.1)
            html = hit.0
            htmlStatus = hit.1
        } catch {
            try throwIfCancelled(error)
            flags.sawNetworkError = true
            return nil
        }
        guard htmlStatus == 200,
              let text = String(data: html, encoding: .utf8),
              text.lowercased().contains("static.status.io"),
              let pageID = extractStatusioPageID(from: text) else {
            return nil
        }
        guard let jsonURL = URL(string: "https://api.status.io/1.0/status/" + pageID) else {
            return nil
        }
        if let hit = try await probeJSON(
            jsonURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: StatusioParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func extractStatusioPageID(from html: String) -> String? {
        guard let regex = statusioPageIDRegex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let inner = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[inner])
    }
}

private extension ProviderProbe {
    static let statusioPageIDRegex: NSRegularExpression? = {
        recordRegex()
        return try? NSRegularExpression(
            pattern: "page_id[\"'\\s:=]+[\"']([a-fA-F0-9]{24})",
            options: []
        )
    }()
}
