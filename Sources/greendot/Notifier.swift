import AppKit
import StatusCore
import UserNotifications

final class Notifier {
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("greendot: notification permission: \(error.localizedDescription)")
            }
        }
    }

    func post(_ toast: Toast) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: Self.content(for: toast),
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func content(for toast: Toast) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = toast.pageName
        content.body = toast.body
        content.sound = .default
        if let icon = icon(for: toast.severity) {
            content.setValue(icon, forKey: "icon")
        }
        return content
    }

    /// Banner icon. `UNNotificationIcon` is in the framework but not the public headers.
    private static func icon(for severity: Severity) -> NSObject? {
        let image = StatusDot.image(severity, size: 64)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              let iconClass = NSClassFromString("UNNotificationIcon") as? NSObject.Type
        else { return nil }
        return iconClass.perform(NSSelectorFromString("iconWithData:"), with: png)?
            .takeUnretainedValue() as? NSObject
    }
}
