import AppKit
import StatusCore
import XCTest
@testable import greendot

final class PanelLifecycleTests: XCTestCase {
    func testReplacingEditPanelDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        var panel: PagePanelController? = PagePanelController(page: page, onSave: { _, _ in })
        panel?.show()
        panel?.close()
        panel = PagePanelController(page: page, onSave: { _, _ in })
        panel?.show()
        panel?.close()
        panel = nil
    }

    private static func nestedPage() -> WatchedPage {
        let group = ComponentStatus(
            name: "Box Web Application",
            severity: .green,
            statusText: "Operational",
            id: "g1",
            children: (1...20).map { i in
                ComponentStatus(
                    name: "Child \(i)",
                    severity: i == 1 ? .red : .green,
                    statusText: "Operational",
                    id: "c\(i)"
                )
            },
            isGroup: true
        )
        return WatchedPage(
            url: URL(string: "https://status.box.com")!,
            name: "Box",
            snapshot: PageSnapshot(
                name: "Box",
                url: URL(string: "https://status.box.com")!,
                provider: .statuspage,
                overall: .green,
                components: [group],
                incidents: [],
                isUnreachable: false
            )
        )
    }
}
