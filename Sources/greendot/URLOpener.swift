import AppKit
import StatusCore

enum URLOpener {
    static func open(_ url: URL) {
        open(
            url,
            logPath: ProcessInfo.processInfo.environment["GREENDOT_OPEN_URL_LOG"],
            workspace: { NSWorkspace.shared.open($0) }
        )
    }

    static func open(_ url: URL, logPath: String?, workspace: (URL) -> Void) {
        let url = URLAuth.strippingUserinfo(url)
        guard isAllowed(url) else { return }
        let path = logPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !path.isEmpty {
            append(url.absoluteString, to: path)
            return
        }
        workspace(url)
    }

    static func isAllowed(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private static func append(_ line: String, to path: String) {
        let data = Data((line + "\n").utf8)
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
