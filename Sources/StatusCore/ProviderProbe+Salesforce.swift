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
        do {
            let (data, status) = try await context.client.get(salesforceActiveIncidentsURL)
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
                let snapshot = try SalesforceParser.parse(
                    data: data,
                    sourceURL: normalizedBase(context.base)
                )
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
    static let salesforceActiveIncidentsURL = URL(
        string: "https://api.status.salesforce.com/v1/incidents/active"
    )!
}
