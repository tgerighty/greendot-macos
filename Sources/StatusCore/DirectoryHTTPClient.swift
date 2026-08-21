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
        if let host = url.host, let hosted = resolve(relative, host: host),
           FileManager.default.fileExists(atPath: hosted.path) {
            return (try Data(contentsOf: hosted), 200)
        }
        if let file = resolve(relative, host: nil),
           FileManager.default.fileExists(atPath: file.path) {
            return (try Data(contentsOf: file), 200)
        }
        return (Data(), 404)
    }

    private func resolve(_ relative: String, host: String?) -> URL? {
        var candidate = root
        if let host {
            guard PathSafety.isPathComponent(host) else { return nil }
            candidate.appendPathComponent(host)
        }
        for part in relative.split(separator: "/") {
            candidate.appendPathComponent(String(part))
        }
        return PathSafety.contained(candidate, under: root)
    }
}
