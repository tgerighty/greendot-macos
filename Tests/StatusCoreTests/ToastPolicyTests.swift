import XCTest
@testable import StatusCore

final class ToastPolicyTests: XCTestCase {
    func testNoToastOnFirstFetch() {
        let current = snap(.red)
        XCTAssertNil(ToastPolicy.toast(
            previous: nil,
            current: current,
            notificationsEnabled: true,
            pageName: "GitHub"
        ))
    }

    func testNoToastWhenDisabled() {
        XCTAssertNil(ToastPolicy.toast(
            previous: snap(.green),
            current: snap(.red),
            notificationsEnabled: false,
            pageName: "GitHub"
        ))
    }

    func testToastWhenOverallColourChanges() {
        let toast = ToastPolicy.toast(
            previous: snap(.green),
            current: snap(.red),
            notificationsEnabled: true,
            pageName: "GitHub"
        )
        XCTAssertEqual(toast?.pageName, "GitHub")
        XCTAssertEqual(toast?.body, "Major outage")
        XCTAssertEqual(toast?.severity, .red)
    }

    func testToastOnRecoveryToGreen() {
        let toast = ToastPolicy.toast(
            previous: snap(.red),
            current: snap(.green),
            notificationsEnabled: true,
            pageName: "GitHub"
        )
        XCTAssertEqual(toast?.body, "Operational")
    }

    func testNoToastWhenColourUnchanged() {
        XCTAssertNil(ToastPolicy.toast(
            previous: snap(.yellow),
            current: snap(.yellow),
            notificationsEnabled: true,
            pageName: "GitHub"
        ))
    }

    func testOnlyGreenToastsAutoDismiss() {
        XCTAssertEqual(Toast(pageName: "GitHub", body: "Operational", severity: .green).autoDismissSeconds, 6)
        for severity in [Severity.red, .yellow, .grey] {
            XCTAssertNil(
                Toast(pageName: "GitHub", body: "Degraded", severity: severity).autoDismissSeconds,
                "\(severity.rawValue) toast must wait for a click"
            )
        }
    }

    private func snap(_ severity: Severity) -> PageSnapshot {
        PageSnapshot(
            name: "GitHub",
            url: URL(string: "https://www.githubstatus.com")!,
            provider: .statuspage,
            overall: severity,
            components: [],
            incidents: [],
            isUnreachable: severity == .grey
        )
    }
}
