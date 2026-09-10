import XCTest
@testable import StatusCore

final class ToastPolicyTests: XCTestCase {
    private let githubID = UUID()

    func testNoToastOnFirstFetch() {
        let current = snap(.red)
        XCTAssertNil(ToastPolicy.toast(
            previous: nil,
            current: current,
            notificationsEnabled: true,
            pageName: "GitHub",
            pageID: githubID
        ))
    }

    func testNoToastWhenDisabled() {
        XCTAssertNil(ToastPolicy.toast(
            previous: snap(.green),
            current: snap(.red),
            notificationsEnabled: false,
            pageName: "GitHub",
            pageID: githubID
        ))
    }

    func testToastWhenOverallColourChanges() {
        let toast = ToastPolicy.toast(
            previous: snap(.green),
            current: snap(.red),
            notificationsEnabled: true,
            pageName: "GitHub",
            pageID: githubID
        )
        XCTAssertEqual(toast?.pageID, githubID)
        XCTAssertEqual(toast?.pageName, "GitHub")
        XCTAssertEqual(toast?.body, "Major outage")
        XCTAssertEqual(toast?.severity, .red)
    }

    func testToastOnRecoveryToGreen() {
        let toast = ToastPolicy.toast(
            previous: snap(.red),
            current: snap(.green),
            notificationsEnabled: true,
            pageName: "GitHub",
            pageID: githubID
        )
        XCTAssertEqual(toast?.pageID, githubID)
        XCTAssertEqual(toast?.body, "Operational")
    }

    func testLeavingGreenAnnouncesItself() {
        for severity in [Severity.yellow, .red, .grey] {
            XCTAssertEqual(
                ToastPolicy.toast(
                    previous: snap(.green),
                    current: snap(severity),
                    notificationsEnabled: true,
                    pageName: "GitHub",
                    pageID: githubID
                )?.silent,
                false,
                "the first \(severity.rawValue) of an episode must announce itself"
            )
        }
    }

    func testAnUnhealthyPageChangingColourStaysQuiet() {
        let unhealthy: [Severity] = [.yellow, .red, .grey]
        for previous in unhealthy {
            for current in unhealthy where current != previous {
                XCTAssertEqual(
                    ToastPolicy.toast(
                        previous: snap(previous),
                        current: snap(current),
                        notificationsEnabled: true,
                        pageName: "GitHub",
                        pageID: githubID
                    )?.silent,
                    true,
                    "\(previous.rawValue) to \(current.rawValue) must not announce itself again"
                )
            }
        }
    }

    func testRecoveryToGreenAnnouncesItself() {
        for severity in [Severity.yellow, .red, .grey] {
            XCTAssertEqual(
                ToastPolicy.toast(
                    previous: snap(severity),
                    current: snap(.green),
                    notificationsEnabled: true,
                    pageName: "GitHub",
                    pageID: githubID
                )?.silent,
                false
            )
        }
    }

    func testNoToastWhenColourUnchanged() {
        XCTAssertNil(ToastPolicy.toast(
            previous: snap(.yellow),
            current: snap(.yellow),
            notificationsEnabled: true,
            pageName: "GitHub",
            pageID: githubID
        ))
    }

    func testOnlyGreenToastsAutoDismiss() {
        XCTAssertEqual(
            Toast(pageID: githubID, pageName: "GitHub", body: "Operational", severity: .green)
                .autoDismissSeconds,
            6
        )
        for severity in [Severity.red, .yellow, .grey] {
            XCTAssertNil(
                Toast(pageID: githubID, pageName: "GitHub", body: "Degraded", severity: severity)
                    .autoDismissSeconds,
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
