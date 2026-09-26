import AppKit
import Foundation

enum BuildInfo {
    static func gitHash(from info: [String: Any]?) -> String {
        let hash = info?["GitCommitHash"] as? String ?? ""
        return hash.isEmpty ? "unknown" : hash
    }

    static func shortHash(from info: [String: Any]?) -> String {
        let hash = gitHash(from: info)
        guard hash != "unknown" else { return hash }
        return String(hash.prefix(7))
    }

    static func version(from info: [String: Any]?) -> String {
        let value = info?["CFBundleShortVersionString"] as? String ?? ""
        return value.isEmpty ? "unknown" : value
    }
}

enum AboutPanel {
    static func options(version: String, gitHash: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        [.applicationVersion: version, .version: gitHash]
    }

    @MainActor
    static func show(
        version: String = BuildInfo.version(from: Bundle.main.infoDictionary),
        gitHash: String = BuildInfo.shortHash(from: Bundle.main.infoDictionary)
    ) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options(version: version, gitHash: gitHash))
    }
}
