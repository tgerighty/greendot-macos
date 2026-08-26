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
}

enum AboutPanel {
    static func options(gitHash: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        [.version: gitHash]
    }

    @MainActor
    static func show(gitHash: String = BuildInfo.shortHash(from: Bundle.main.infoDictionary)) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options(gitHash: gitHash))
    }
}
