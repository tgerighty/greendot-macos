import AppKit
import StatusCore
import UserNotifications

protocol UserNotificationCenterClient: AnyObject, Sendable {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping @Sendable (Bool, Error?) -> Void
    )
    func add(_ request: UNNotificationRequest)
    func getDeliveredRequests(
        completion: @escaping @Sendable ([UNNotificationRequest]) -> Void
    )
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

/// Defers the process-bound system center until delivery starts, with synchronized first access.
private final class LiveUserNotificationCenterClient: UserNotificationCenterClient, @unchecked Sendable {
    private let centerLock = NSLock()
    private var storedCenter: UNUserNotificationCenter?

    private var center: UNUserNotificationCenter {
        centerLock.lock()
        defer { centerLock.unlock() }
        if let storedCenter { return storedCenter }
        let center = UNUserNotificationCenter.current()
        storedCenter = center
        return center
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        center.requestAuthorization(options: options, completionHandler: completion)
    }

    func add(_ request: UNNotificationRequest) {
        center.add(request)
    }

    func getDeliveredRequests(
        completion: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        center.getDeliveredNotifications { delivered in
            completion(delivered.map(\.request))
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

typealias ToastScheduler = @MainActor (
    TimeInterval,
    @escaping @MainActor @Sendable () -> Void
) -> Void

final class SystemToastDelivery: ToastDelivery {
    /// Marks the toasts that clear themselves, so a stale one can be cleared at the next launch.
    static let autoDismissCategory = "greendot-auto-dismiss"

    private let notifications: any UserNotificationCenterClient
    private let schedule: ToastScheduler
    private let makeIdentifier: () -> String
    private var persistent: PersistentToastPresenter?

    init() {
        notifications = LiveUserNotificationCenterClient()
        schedule = { seconds, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                action()
            }
        }
        makeIdentifier = { UUID().uuidString }
        persistent = nil
    }

    init(
        notifications: any UserNotificationCenterClient,
        schedule: @escaping ToastScheduler,
        makeIdentifier: @escaping () -> String,
        persistent: PersistentToastPresenter? = nil
    ) {
        self.notifications = notifications
        self.schedule = schedule
        self.makeIdentifier = makeIdentifier
        self.persistent = persistent
    }

    @MainActor
    func start() {
        requestPermissionIfNeeded()
        clearStaleAutoDismissToasts()
    }

    @MainActor
    func deliver(_ toast: Toast) {
        guard let seconds = toast.autoDismissSeconds else {
            persistentPresenter().present(toast)
            return
        }
        persistent?.clear(pageID: toast.pageID)
        let identifier = makeIdentifier()
        let request = UNNotificationRequest(
            identifier: identifier,
            content: Self.content(for: toast),
            trigger: nil
        )
        notifications.add(request)
        let notifications = notifications
        schedule(seconds) {
            notifications.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    @MainActor
    private func persistentPresenter() -> PersistentToastPresenter {
        if let persistent { return persistent }
        let created = PanelPersistentToastPresenter()
        persistent = created
        return created
    }

    @MainActor
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

    private func requestPermissionIfNeeded() {
        notifications.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("greendot: notification permission: \(error.localizedDescription)")
            }
        }
    }

    /// Clears toasts that a quit cut short before they could clear themselves.
    private func clearStaleAutoDismissToasts() {
        notifications.getDeliveredRequests { [notifications] delivered in
            let stale = delivered
                .filter { $0.content.categoryIdentifier == Self.autoDismissCategory }
                .map(\.identifier)
            guard !stale.isEmpty else { return }
            notifications.removeDeliveredNotifications(withIdentifiers: stale)
        }
    }

    @MainActor
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
