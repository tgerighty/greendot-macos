import Foundation

public func testURL(host: String, path: String = "") -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host
    components.path = path

    guard let url = components.url else {
        preconditionFailure("Invalid test URL for host: \(host)")
    }
    return url
}
