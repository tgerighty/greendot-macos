import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        guard !isEnabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("greendot: launch at login enable failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func toggle() -> Bool {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            return true
        } catch {
            NSLog("greendot: launch at login failed: \(error.localizedDescription)")
            return false
        }
    }
}
