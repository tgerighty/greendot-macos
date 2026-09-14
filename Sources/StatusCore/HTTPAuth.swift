import Foundation

enum HTTPAuth {
    static func requestURL(_ url: URL) -> URL {
        URLAuth.strippingUserinfo(url)
    }

    static func headers(for url: URL) -> [String: String] {
        var headers: [String: String] = [:]
        if let user = url.user {
            let password = url.password ?? ""
            let token = Data("\(user):\(password)".utf8).base64EncodedString()
            headers["Authorization"] = "Basic \(token)"
        }
        if ProviderProbe.isIcingaAPI(url) {
            headers["Accept"] = "application/json"
        }
        return headers
    }
}

enum TLSTrust {
    static func allowsInsecureServerTrust(for url: URL) -> Bool {
        ProviderProbe.isIcingaAPI(url)
    }
}
