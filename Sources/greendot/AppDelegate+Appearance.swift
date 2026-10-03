import AppKit
import StatusCore

extension AppDelegate {
    @MainActor
    func setInterfaceStyle(_ style: InterfaceStyle) {
        guard let monitor else { return }
        let previous = GreendotStyle.choice
        GreendotStyle.choice = style
        StatusDot.clearCache()
        guard performStoreChange({ try monitor.setInterfaceStyle(style) }) else {
            GreendotStyle.choice = previous
            StatusDot.clearCache()
            return
        }
        GreendotStyle.refreshOpenWindows()
        statusMenu?.refreshAppearance()
    }

    @MainActor
    func observeSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                StatusDot.clearCache()
                self?.statusMenu?.refreshAppearance()
            }
        }
    }
}
