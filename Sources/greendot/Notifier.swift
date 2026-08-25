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

    static func content(for toast: Toast) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = toast.pageName
        content.body = toast.body
        content.sound = .default
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
