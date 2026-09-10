import AppKit
import StatusCore
import XCTest
@testable import greendot

/// A page that is already unhealthy must not announce itself again when its colour moves.
@MainActor
final class SilentToastTests: XCTestCase {
    private let githubID = UUID()
    private static let silentSound: () -> Void = {
        // Tests do not play a sound.
    }

    func testSilentToastRecoloursTheOpenPanelWithoutASound() {
        _ = NSApplication.shared
        var sounds = 0
        let presenter = PanelPersistentToastPresenter(playSound: { sounds += 1 })
        presenter.present(toast(body: "Degraded", severity: .yellow))
        XCTAssertEqual(sounds, 1)

        presenter.update(toast(body: "Unreachable", severity: .grey, silent: true))

        XCTAssertEqual(sounds, 1)
        XCTAssertEqual(presenter.visibleCount, 1)
        XCTAssertEqual(
            presenter.windows.first?.contentView?.accessibilityLabel(),
            "GitHub, Unreachable"
        )
    }

    func testSilentToastLeavesAClearedPageAlone() {
        _ = NSApplication.shared
        var sounds = 0
        let presenter = PanelPersistentToastPresenter(playSound: { sounds += 1 })
        presenter.present(toast(body: "Degraded", severity: .yellow))
        presenter.windows.first?.contentView?.mouseDown(with: NSEvent())
        XCTAssertEqual(presenter.visibleCount, 0)

        presenter.update(toast(body: "Unreachable", severity: .grey, silent: true))

        XCTAssertEqual(presenter.visibleCount, 0, "an acknowledged page must not come back on its own")
        XCTAssertEqual(sounds, 1)
    }

    func testSilentToastKeepsTheStackOrder() {
        _ = NSApplication.shared
        let presenter = PanelPersistentToastPresenter(playSound: Self.silentSound)
        let first = UUID()
        presenter.present(toast(pageID: first, pageName: "Page 1", body: "Degraded", severity: .yellow))
        presenter.present(toast(pageID: UUID(), pageName: "Page 2", body: "Degraded", severity: .yellow))

        presenter.update(
            toast(pageID: first, pageName: "Page 1", body: "Unreachable", severity: .grey, silent: true)
        )

        XCTAssertEqual(
            presenter.windows.compactMap { $0.contentView?.accessibilityLabel() },
            ["Page 1, Unreachable", "Page 2, Degraded"]
        )
    }

    func testDeliverRoutesASilentToastToAnUpdate() {
        let persistent = RecordingPersistentToastPresenter()
        let delivery = SystemToastDelivery(
            notifications: RecordingUserNotificationCenter(),
            schedule: { _, _ in },
            makeIdentifier: { "unused" },
            persistent: persistent
        )

        delivery.deliver(toast(body: "Unreachable", severity: .grey, silent: true))

        XCTAssertEqual(persistent.presented, [])
        XCTAssertEqual(persistent.updated.map(\.body), ["Unreachable"])
    }

    private func toast(
        pageID: UUID? = nil,
        pageName: String = "GitHub",
        body: String,
        severity: Severity,
        silent: Bool = false
    ) -> Toast {
        Toast(
            pageID: pageID ?? githubID,
            pageName: pageName,
            body: body,
            severity: severity,
            silent: silent
        )
    }
}
