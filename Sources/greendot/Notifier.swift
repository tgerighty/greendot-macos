import AppKit
import StatusCore
import UserNotifications

final class Notifier {
    /// Marks the toasts that clear themselves, so a stale one can be cleared at the next launch.
    static let autoDismissCategory = "greendot-auto-dismiss"

    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("greendot: notification permission: \(error.localizedDescription)")
            }
        }
    }

    func post(_ toast: Toast) {
        let identifier = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: Self.content(for: toast),
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.add(request)
        guard let seconds = toast.autoDismissSeconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    /// Clears toasts that a quit cut short before they could clear themselves.
    func clearStaleAutoDismissToasts() {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let stale = delivered
                .filter { $0.request.content.categoryIdentifier == Self.autoDismissCategory }
                .map(\.request.identifier)
            guard !stale.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    static func content(for toast: Toast) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = toast.pageName
        content.body = toast.body
        content.sound = .default
        if toast.autoDismissSeconds != nil {
            content.categoryIdentifier = autoDismissCategory
        }
        if let attachment = attachment(for: toast.severity) {
            content.attachments = [attachment]
        }
        return content
    }

    private static func attachment(for severity: Severity) -> UNNotificationAttachment? {
        let image = StatusDot.image(severity, size: 64)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("greendot-\(severity.rawValue)-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(
                identifier: "status-\(severity.rawValue)",
                url: url,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
