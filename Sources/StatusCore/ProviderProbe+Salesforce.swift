import Foundation

extension ProviderProbe {
    static func isSalesforceLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.salesforce.com" else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty
    }

    static func probeSalesforceIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isSalesforceLanding(context.base) || isSalesforceLanding(context.pageURL) else { return nil }
        if let hit = try await probeSalesforce(context: context, flags: &flags) {
            return hit
        }
        throw flags.finalError
    }

    static func probeSalesforce(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        try await probeJSON(
            salesforceActiveIncidentsURL,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: SalesforceParser.parse
        )
    }
}

private extension ProviderProbe {
    static let salesforceActiveIncidentsURL = URL(
        string: "https://api.status.salesforce.com/v1/incidents/active"
    )!
}
