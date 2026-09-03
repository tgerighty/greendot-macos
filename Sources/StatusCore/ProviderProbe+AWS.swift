import Foundation

extension ProviderProbe {
    static func isAWSLanding(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch host {
        case "health.aws.amazon.com":
            return path.isEmpty || path == "health/status" || path == "public/currentevents"
        case "status.aws.amazon.com":
            return path.isEmpty
        default:
            return false
        }
    }

    static func probeAWSIfLanding(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isAWSLanding(context.base) else { return nil }
        if let hit = try await probeAWS(context: context, flags: &flags) {
            return hit
        }
        throw flags.finalError
    }

    static func probeAWS(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        do {
            let (data, status) = try await context.client.get(awsCurrentEventsURL)
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
                let snapshot = try AwsParser.parse(data: data, sourceURL: awsClickURL(context.base))
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
    static let awsCurrentEventsURL = URL(string: "https://health.aws.amazon.com/public/currentevents")!
    static let awsHealthStatusURL = URL(string: "https://health.aws.amazon.com/health/status")!

    static func awsClickURL(_ base: URL) -> URL {
        let host = base.host?.lowercased() ?? ""
        let path = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        if host == "health.aws.amazon.com", path == "public/currentevents" {
            return awsHealthStatusURL
        }
        return base
    }
}
