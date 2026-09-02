import AppKit
import StatusCore
import UserNotifications
import XCTest
@testable import greendot

@MainActor
final class SystemToastDeliveryTests: XCTestCase {
    private let githubID = UUID()

    func testStartRequestsPermissionThenClearsOnlyStaleAutoDismissToasts() {
        let notifications = RecordingUserNotificationCenter()
        notifications.deliveredRequests = [
            Self.request(identifier: "stale-green", category: SystemToastDelivery.autoDismissCategory),
            Self.request(identifier: "persistent-red", category: "")
        ]
        let delivery = SystemToastDelivery(
            notifications: notifications,
            schedule: { _, _ in
                XCTFail("Starting toast delivery must not schedule a removal")
            },
            makeIdentifier: { "unused" }
        )

        delivery.start()

        XCTAssertEqual(notifications.calls.prefix(2), ["authorization", "delivered"])
        XCTAssertTrue(notifications.authorizationOptions.contains(.alert))
        XCTAssertTrue(notifications.authorizationOptions.contains(.sound))
        XCTAssertEqual(notifications.removedIdentifiers, [["stale-green"]])
    }

    func testDeliverAddsImmediateRequestsAndOnlySchedulesGreenRemoval() throws {
        let notifications = RecordingUserNotificationCenter()
        let persistent = RecordingPersistentToastPresenter()
        var scheduledDelays: [TimeInterval] = []
        var scheduledActions: [() -> Void] = []
        var identifiers = ["green-id", "red-id"].makeIterator()
        let delivery = SystemToastDelivery(
            notifications: notifications,
            schedule: { delay, action in
                scheduledDelays.append(delay)
                scheduledActions.append(action)
            },
            makeIdentifier: { identifiers.next() ?? "unexpected-id" },
            persistent: persistent
        )

        delivery.deliver(toast(body: "Operational", severity: .green))
        delivery.deliver(toast(body: "Major outage", severity: .red))
        delivery.deliver(toast(body: "Degraded", severity: .yellow))

        XCTAssertEqual(notifications.addedRequests.map(\.identifier), ["green-id"])
        let green = try XCTUnwrap(notifications.addedRequests.first)
        XCTAssertNil(green.trigger)
        XCTAssertEqual(green.content.title, "GitHub")
        XCTAssertEqual(green.content.body, "Operational")
        XCTAssertNotNil(green.content.sound)
        XCTAssertEqual(green.content.categoryIdentifier, SystemToastDelivery.autoDismissCategory)
        XCTAssertEqual(scheduledDelays, [6])
        XCTAssertTrue(notifications.removedIdentifiers.isEmpty)
        XCTAssertEqual(persistent.presented.map(\.severity), [.red, .yellow])
        XCTAssertEqual(persistent.presented.map(\.body), ["Major outage", "Degraded"])

        try XCTUnwrap(scheduledActions.first)()

        XCTAssertEqual(notifications.removedIdentifiers, [["green-id"]])
    }

    func testToastAttachmentColourMatchesIssueColour() {
        _ = NSApplication.shared
        for severity in [Severity.red, .yellow, .green, .grey] {
            let payload = toast(body: "Major outage", severity: severity)
            let content = SystemToastDelivery.content(for: payload)
            XCTAssertEqual(content.title, "GitHub")
            XCTAssertEqual(content.body, "Major outage")
            guard let png = Self.attachmentPNG(content),
                  let sampled = Self.centerColor(png) else {
                XCTFail("missing toast image for \(severity.rawValue)")
                continue
            }
            XCTAssertEqual(
                Self.nearestSeverity(to: sampled),
                severity,
                "toast image for \(severity.rawValue) sampled \(sampled)"
            )
        }
    }

    func testPersistentPanelStaysUntilClicked() {
        _ = NSApplication.shared
        let presenter = PanelPersistentToastPresenter(playSound: {})
        presenter.present(toast(body: "Major outage", severity: .red))
        XCTAssertEqual(presenter.visibleCount, 1)
        let card = presenter.windows.first?.contentView as? NSView
        XCTAssertEqual(card?.accessibilityIdentifier(), "persistent-toast-card")
        let hit = card?.hitTest(NSPoint(x: 80, y: 40))
        XCTAssertTrue(hit === card, "text and icon clicks must hit the card")
        card?.mouseDown(with: NSEvent())
        XCTAssertEqual(presenter.visibleCount, 0)
        presenter.present(toast(body: "Major outage", severity: .red))
        XCTAssertEqual(presenter.visibleCount, 1)
        XCTAssertTrue(presenter.windows.first?.contentView?.accessibilityPerformPress() == true)
        XCTAssertEqual(presenter.visibleCount, 0)
    }

    func testPersistentPanelReplacesSamePageAndCapsStack() {
        _ = NSApplication.shared
        let presenter = PanelPersistentToastPresenter(playSound: {})
        presenter.present(toast(body: "Major outage", severity: .red))
        presenter.present(toast(body: "Degraded", severity: .yellow))
        XCTAssertEqual(presenter.visibleCount, 1)
        for index in 1...10 {
            presenter.present(
                toast(pageID: UUID(), pageName: "Page \(index)", body: "Degraded", severity: .yellow)
            )
        }
        XCTAssertEqual(presenter.visibleCount, 8)
    }

    func testPersistentPanelQueuesOverflowUntilASlotFrees() {
        _ = NSApplication.shared
        let presenter = PanelPersistentToastPresenter(playSound: {})
        for index in 1...8 {
            presenter.present(
                toast(pageID: UUID(), pageName: "Page \(index)", body: "Degraded", severity: .yellow)
            )
        }
        XCTAssertEqual(presenter.visibleCount, 8)
        presenter.present(
            toast(pageID: UUID(), pageName: "Page 9", body: "Major outage", severity: .red)
        )
        XCTAssertEqual(presenter.visibleCount, 8)
        presenter.windows.first?.contentView?.mouseDown(with: NSEvent())
        XCTAssertEqual(presenter.visibleCount, 8)
    }

    func testPersistentPanelKeepsDistinctPagesThatShareAName() {
        _ = NSApplication.shared
        let presenter = PanelPersistentToastPresenter(playSound: {})
        presenter.present(
            toast(pageID: UUID(), pageName: "GitHub", body: "Major outage", severity: .red)
        )
        presenter.present(
            toast(pageID: UUID(), pageName: "GitHub", body: "Degraded", severity: .yellow)
        )
        XCTAssertEqual(presenter.visibleCount, 2)
    }

    func testOnlyAutoDismissToastsCarryTheClearOnLaunchCategory() {
        _ = NSApplication.shared
        let green = SystemToastDelivery.content(
            for: toast(body: "Operational", severity: .green)
        )
        XCTAssertEqual(green.categoryIdentifier, SystemToastDelivery.autoDismissCategory)
        for severity in [Severity.red, .yellow, .grey] {
            let content = SystemToastDelivery.content(
                for: toast(body: "Degraded", severity: severity)
            )
            XCTAssertEqual(
                content.categoryIdentifier,
                "",
                "\(severity.rawValue) toast must not be cleared on launch"
            )
        }
    }

    private static func attachmentPNG(_ content: UNMutableNotificationContent) -> Data? {
        guard let url = content.attachments.first?.url else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try? Data(contentsOf: url)
    }

    private static func centerColor(_ png: Data) -> NSColor? {
        guard let rep = NSBitmapImageRep(data: png),
              let color = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)
        else { return nil }
        return color.usingColorSpace(.deviceRGB)
    }

    private static func nearestSeverity(to color: NSColor) -> Severity {
        let candidates: [Severity] = [.red, .yellow, .green, .grey]
        return candidates.min { lhs, rhs in
            distance(color, StatusDot.color(lhs)) < distance(color, StatusDot.color(rhs))
        } ?? .green
    }

    private static func distance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let left = lhs.usingColorSpace(.deviceRGB) ?? lhs
        let right = rhs.usingColorSpace(.deviceRGB) ?? rhs
        let red = left.redComponent - right.redComponent
        let green = left.greenComponent - right.greenComponent
        let blue = left.blueComponent - right.blueComponent
        return red * red + green * green + blue * blue
    }

    private func toast(
        pageID: UUID? = nil,
        pageName: String = "GitHub",
        body: String,
        severity: Severity
    ) -> Toast {
        Toast(
            pageID: pageID ?? githubID,
            pageName: pageName,
            body: body,
            severity: severity
        )
    }

    private static func request(identifier: String, category: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }
}

private final class RecordingPersistentToastPresenter: PersistentToastPresenter {
    var presented: [Toast] = []

    func present(_ toast: Toast) {
        presented.append(toast)
    }
}

/// Used only by main-actor tests and completes every callback synchronously.
private final class RecordingUserNotificationCenter: UserNotificationCenterClient, @unchecked Sendable {
    var calls: [String] = []
    var authorizationOptions: UNAuthorizationOptions = []
    var addedRequests: [UNNotificationRequest] = []
    var deliveredRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [[String]] = []

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        calls.append("authorization")
        authorizationOptions = options
        completion(true, nil)
    }

    func add(_ request: UNNotificationRequest) {
        calls.append("add")
        addedRequests.append(request)
    }

    func getDeliveredRequests(
        completion: @escaping @Sendable ([UNNotificationRequest]) -> Void
    ) {
        calls.append("delivered")
        completion(deliveredRequests)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        calls.append("remove")
        removedIdentifiers.append(identifiers)
    }
}
