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
        do {
            let (data, status) = try await context.client.get(context.base)
            try Task.checkCancellation()
            flags.recordHTTP(status: status)
            let body = Data("HTTP \(status)\n".utf8) + data
            guard status == 200 else { return nil }
            if let previousBody = context.previousBody,
               let previousSnapshot = context.previousSnapshot,
               !previousSnapshot.isUnreachable,
               body == previousBody {
                return ProbeHit(snapshot: previousSnapshot, body: body)
            }
            do {
                recordParse()
                let snapshot = try OktaParser.parse(data: data, sourceURL: context.base)
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
