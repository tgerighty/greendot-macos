import Foundation

extension ProviderProbe {
    static func probeKnownLandings(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        if let hit = try await probePlatformLandings(context: context, flags: &flags) {
            return hit
        }
        return try await probeDirectLandings(context: context, flags: &flags)
    }

    static func probePlatformLandings(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
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
        return try await probeAppleIfLanding(context: context, flags: &flags)
    }

    static func probeDirectLandings(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        if let hit = try await probeStripeIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeBitBarIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeZoomIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeClaudeIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeConcurIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeAdobeIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeAzureDevOpsIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeN8nIfLanding(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeZscalerIfLanding(context: context, flags: &flags) {
            return hit
        }
        return try await probeQlikIfLanding(context: context, flags: &flags)
    }

    static func probeSlackIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isSlackLanding(context.base) || isSlackLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            slackCurrentURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: SlackParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeHerokuIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isHerokuLanding(context.base) || isHerokuLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            herokuCurrentURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: HerokuParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeGoogleIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard let jsonURL = googleIncidentsURL(context.base) ?? googleIncidentsURL(context.pageURL) else {
            return nil
        }
        if let hit = try await probeJSON(
            jsonURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: GoogleParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeAppleIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isAppleLanding(context.base) || isAppleLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            appleStatusURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: AppleParser.parse
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeBitBarIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isBitBarLanding(context.base) || isBitBarLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            bitBarStatuspageURL,
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

    static func probeStripeIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isStripeLanding(context.base) || isStripeLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            stripeStatuspageURL,
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

    static func probeIncidentio(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        let host = context.base.host?.lowercased() ?? ""
        guard host == "status.incident.io" || host.hasSuffix(".incident.io") else {
            return nil
        }
        let jsonURL = context.base.appendingPathComponent("proxy").appendingPathComponent("status.incident.io")
        return try await probeJSON(
            jsonURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: IncidentioParser.parse
        )
    }

    static func isSlackLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "slack-status.com" || host == "status.slack.com" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func isHerokuLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.heroku.com" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func isAppleLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "apple.com" || host == "www.apple.com" else { return false }
        return url.path.lowercased().contains("support/systemstatus")
    }

    static func isBitBarLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.bitbar.com" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func probeZoomIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isZoomLanding(context.base) || isZoomLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            zoomStatuspageURL,
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

    static func isZoomLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.zoom.us" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func probeClaudeIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isClaudeLanding(context.base) || isClaudeLanding(context.pageURL) else { return nil }
        if let hit = try await probeJSON(
            claudeStatuspageURL,
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

    static func isClaudeLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.claude.com" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func isStripeLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.stripe.com" else { return false }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
    }

    static func googleIncidentsURL(_ url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        if host == "status.cloud.google.com" || host == "status.firebase.google.com" {
            return URL(string: "https://\(host)/incidents.json")
        }
        if host == "www.google.com" || host == "google.com", path.contains("appsstatus") {
            return URL(string: "https://www.google.com/appsstatus/dashboard/incidents.json")
        }
        return nil
    }
}

extension ProviderProbe {
    static func probeJSON(
        _ jsonURL: URL,
        sourceURL: URL,
        context: ProbeContext,
        flags: inout ProbeFlags,
        parse: (Data, URL) throws -> PageSnapshot
    ) async throws -> ProbeHit? {
        do {
            let (data, status) = try await context.client.get(jsonURL)
            try Task.checkCancellation()
            flags.recordHTTP(status: status)
            let body = Data("HTTP \(status)\n".utf8) + data
            guard status == 200 else { return nil }
            if let hit = context.cachedHit(for: body) { return hit }
            do {
                recordParse()
                let snapshot = try parse(data, normalizedBase(sourceURL))
                return ProbeHit(snapshot: snapshot, body: body)
            } catch {
                return nil
            }
        } catch {
            try throwIfCancelled(error)
            flags.sawNetworkError = true
            return nil
        }
    }
}

private extension ProviderProbe {
    static let slackCurrentURL = URL(string: "https://slack-status.com/api/v2.0.0/current")!
    static let herokuCurrentURL = URL(string: "https://status.heroku.com/api/v4/current-status")!
    static let appleStatusURL = URL(string: "https://www.apple.com/support/systemstatus/data/system_status_en_US.js")!
    static let stripeStatuspageURL = URL(string: "https://www.stripestatus.com/api/v2/summary.json")!
    static let bitBarStatuspageURL = URL(string: "https://bitbar.status.smartbear.com/api/v2/summary.json")!
    static let zoomStatuspageURL = URL(string: "https://www.zoomstatus.com/api/v2/summary.json")!
    static let claudeStatuspageURL = URL(string: "https://status.claude.com/api/v2/summary.json")!
}
