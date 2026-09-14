import Foundation

public enum URLAuth {
    public static func strippingUserinfo(_ url: URL) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.user = nil
        parts.password = nil
        return parts.url ?? url
    }
}
