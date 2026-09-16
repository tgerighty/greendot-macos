import Foundation

extension ProviderProbe {
    static func probeHit(
        pageURL: URL,
        client: HTTPClient,
        prefer: StatusProvider? = nil,
        previousBody: Data? = nil,
        previousSnapshot: PageSnapshot? = nil
    ) async throws -> ProbeHit {
        let context = ProbeContext(
            base: normalizedBase(pageURL),
            pageURL: pageURL,
            client: client,
            previousBody: previousBody,
            previousSnapshot: previousSnapshot
        )
        var flags = ProbeFlags()
        if let hit = try await probeKnownLandings(context: context, flags: &flags) {
            return hit
        }
        if let hit = try await probeOrderedProviders(
            preferring: prefer,
            context: context,
            flags: &flags
        ) {
            return hit
        }
        throw flags.finalError
    }

    static func probeOrderedProviders(
        preferring prefer: StatusProvider?,
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        for provider in probeOrder(preferring: prefer) {
            if let hit = try await probeOneProvider(provider, context: context, flags: &flags) {
                return hit
            }
        }
        return nil
    }

    static func probeOneProvider(
        _ provider: StatusProvider,
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        switch provider {
        case .statuspage, .instatus, .flashduty:
            return flags.record(try await standardAttempt(for: provider, context: context))
        case .statuspal:
            return try await probeStatuspal(context: context, flags: &flags)
        case .statusio:
            return try await probeStatusio(context: context, flags: &flags)
        case .incidentio:
            return try await probeIncidentio(context: context, flags: &flags)
        case .rss:
            return try await probeRSS(context: context, flags: &flags)
        case .aws, .icinga, .okta, .salesforce, .slack, .heroku, .google, .apple:
            return nil
        }
    }
}
