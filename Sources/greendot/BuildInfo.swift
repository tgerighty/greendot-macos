import AppKit
import Foundation

enum BuildInfo {
    static var gitHash: String {
        gitHash(from: Bundle.main.infoDictionary)
    }

    static func gitHash(from info: [String: Any]?) -> String {
        let hash = info?["GitCommitHash"] as? String ?? ""
        return hash.isEmpty ? "unknown" : hash
    }
}

enum AboutPanel {
    static func options(gitHash: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        [.version: gitHash]
    }

    static func show(gitHash: String = BuildInfo.gitHash) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options(gitHash: gitHash))
    }
}
