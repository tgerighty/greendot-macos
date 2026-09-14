import Foundation

extension ProviderProbe {
    static func isIcingaAPI(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "v1" || path.hasPrefix("v1/") else { return false }
        if url.port == 5665 { return true }
        return (url.host ?? "").localizedCaseInsensitiveContains("icinga")
    }

    static func probeIcingaIfAPI(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard isIcingaAPI(context.pageURL) || isIcingaAPI(context.base) else { return nil }
        if let hit = try await probeIcinga(context: context, flags: &flags) {
            return hit
        }
        throw flags.finalError
    }

    static func probeIcinga(
        context: ProbeContext,
        flags: inout ProbeFlags
    ) async throws -> ProbeHit? {
        guard let base = icingaAPIBase(context.pageURL) ?? icingaAPIBase(context.base) else { return nil }
        let hostsURL = base.appendingPathComponent("objects").appendingPathComponent("hosts")
        let servicesURL = base.appendingPathComponent("objects").appendingPathComponent("services")
        do {
            guard let hosts = try await fetchIcingaObject(hostsURL, client: context.client, flags: &flags),
                  let services = try await fetchIcingaObject(servicesURL, client: context.client, flags: &flags) else {
                return nil
            }
            let body = Data("HTTP \(hosts.status) \(services.status)\n".utf8)
                + hosts.data
                + Data("\n--\n".utf8)
                + services.data
            if let previousBody = context.previousBody,
               let previousSnapshot = context.previousSnapshot,
               !previousSnapshot.isUnreachable,
               body == previousBody {
                return ProbeHit(snapshot: previousSnapshot, body: body)
            }
            do {
                recordParse()
                let snapshot = try IcingaParser.parse(
                    hosts: hosts.data,
                    services: services.data,
                    sourceURL: context.pageURL
                )
                return ProbeHit(snapshot: snapshot, body: body)
            } catch {
                return nil
            }
        } catch let error as ProbeError {
            throw error
        } catch {
            try throwIfCancelled(error)
            flags.sawNetworkError = true
            return nil
        }
    }
}

private extension ProviderProbe {
    struct IcingaObjectResponse {
        let data: Data
        let status: Int
    }

    static func icingaAPIBase(_ url: URL) -> URL? {
        guard isIcingaAPI(url) else { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.query = nil
        parts.fragment = nil
        parts.path = "/v1"
        return parts.url
    }

    static func fetchIcingaObject(
        _ url: URL,
        client: HTTPClient,
        flags: inout ProbeFlags
    ) async throws -> IcingaObjectResponse? {
        let (data, status) = try await client.get(url)
        try Task.checkCancellation()
        if status == 401 || status == 403 {
            throw ProbeError.unauthorized
        }
        flags.recordHTTP(status: status)
        guard status == 200 else { return nil }
        return IcingaObjectResponse(data: data, status: status)
    }
}
