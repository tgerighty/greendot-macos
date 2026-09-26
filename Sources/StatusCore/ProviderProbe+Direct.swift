import Foundation

extension ProviderProbe {
    static let concurDatacenters = ["us", "us2", "eu2", "apj1", "usg"]
    static let adobeStatusEventsURL = URL(
        string: "https://data.status.adobe.com/adobestatus/StatusEvents"
    )!
    static let azureDevOpsHealthURL = URL(
        string: "https://status.dev.azure.com/_apis/status/health"
    )!
    static let zscalerBannerURL = URL(string: "https://trust.zscaler.com/api/cloud-banner")!
    static let qlikStatuspageURL = URL(
        string: "https://statusa-an5d9w.qlikcloud.com/api/v2/summary.json"
    )!

    static func probeConcurIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "open.concur.com") else { return nil }
        var groups: [ComponentStatus] = []
        for datacenter in concurDatacenters {
            guard let url = concurURL(datacenter) else { continue }
            let (data, status) = try await context.client.get(url)
            flags.recordHTTP(status: status)
            guard status == 200 else { continue }
            if let group = try? ConcurParser.serviceGroup(data: data, datacenter: datacenter) {
                groups.append(group)
            }
        }
        guard !groups.isEmpty else { throw flags.finalError }
        let snapshot = DirectStatus.snapshot(
            name: "SAP Concur",
            url: context.base,
            provider: .concur,
            components: groups
        )
        return ProbeHit(snapshot: snapshot, body: Data("concur".utf8))
    }

    static func probeAdobeIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "status.adobe.com") else { return nil }
        if let hit = try await probeJSON(
            adobeStatusEventsURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: AdobeParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeAzureDevOpsIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "status.dev.azure.com") else { return nil }
        if let hit = try await probeJSON(
            azureDevOpsHealthURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: AzureDevOpsParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeN8nIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "status.n8n.cloud") else { return nil }
        let (html, status) = try await context.client.get(context.base)
        flags.recordHTTP(status: status)
        guard status == 200,
              let text = String(data: html, encoding: .utf8),
              let listID = n8nMonitorListID(text) else {
            throw flags.finalError
        }
        let listURL = context.base
            .appendingPathComponent("api")
            .appendingPathComponent("getMonitorList")
            .appendingPathComponent(listID)
        if let hit = try await probeJSON(
            listURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: N8nParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeZscalerIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "trust.zscaler.com") else { return nil }
        if let hit = try await probeJSON(
            zscalerBannerURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: ZscalerParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeQlikIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHost(context, "status.qlikcloud.com") else { return nil }
        if let hit = try await probeJSON(
            qlikStatuspageURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: { data, url in
                var snap = try StatuspageParser.parse(data: data, sourceURL: url)
                snap.url = normalizedBase(url)
                return snap
            }
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func isHost(_ context: ProbeContext, _ host: String) -> Bool {
        let pageHost = context.base.host?.lowercased() ?? ""
        let rawHost = context.pageURL.host?.lowercased() ?? ""
        return pageHost == host || rawHost == host
    }

    static func concurURL(_ datacenter: String) -> URL? {
        var parts = URLComponents(string: "https://open.concur.com/api/v2/status_history")
        parts?.queryItems = [URLQueryItem(name: "data_center", value: datacenter)]
        return parts?.url
    }

    static func n8nMonitorListID(_ html: String) -> String? {
        guard let regex = n8nMonitorListRegex else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let idRange = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[idRange])
    }

    static let n8nMonitorListRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "getMonitorList/([A-Za-z0-9]+)"
    )
}
