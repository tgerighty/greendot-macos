import Foundation

/// Maps a request path onto files under `root`. Used by UI tests so they do not
/// need a real HTTP server in the XCTest runner process.
public struct DirectoryHTTPClient: HTTPClient, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func get(_ url: URL) async throws -> (Data, Int) {
        var relative = url.path
        while relative.hasPrefix("/") { relative.removeFirst() }
        guard !relative.isEmpty else { return (Data(), 404) }
        if let host = url.host, !host.isEmpty {
            let hosted = root.appendingPathComponent(host).appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: hosted.path) {
                return (try Data(contentsOf: hosted), 200)
            }
        }
        let file = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: file.path) else {
            return (Data(), 404)
        }
        let data = try Data(contentsOf: file)
        return (data, 200)
    }
}
