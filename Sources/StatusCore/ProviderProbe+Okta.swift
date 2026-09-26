import Foundation

extension ProviderProbe {
    static func isOktaLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        guard host == "status.okta.com" else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty
    }

    static func probeOktaIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isOktaLanding(context.base) || isOktaLanding(context.pageURL) else { return nil }
        if let hit = try await probeOkta(context: context, flags: &flags) {
            return hit
        }
        throw flags.finalError
    }

    static func probeOkta(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        try await probeJSON(
            context.base,
            sourceURL: context.base,
            context: context,
            flags: &flags,
            parse: OktaParser.parse
        )
    }
}
