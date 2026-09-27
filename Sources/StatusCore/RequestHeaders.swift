import Foundation

public enum RequestHeaders {
    /// Gives the Authorization header map for a page read token.
    /// A nil token or an empty token gives an empty map.
    public static func authorization(token: String?) -> [String: String] {
        guard let token, !token.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}
