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

    func testCloseAfterWindowCloseDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(page: page, onSave: { _, _ in })
        panel.show()
        panel.closeWindow()
        panel.close()
    }

    func testReplacingEditPanelFiveTimesDoesNotCrash() {
        _ = NSApplication.shared
        let first = Self.nestedPage(name: "OpenAI")
        let second = Self.nestedPage(name: "Box")
        var panel: PagePanelController?
        for _ in 1...5 {
            panel?.close()
            panel = PagePanelController(page: first, onSave: { _, _ in })
            panel?.show()
            panel?.close()
            panel = PagePanelController(page: second, onSave: { _, _ in })
            panel?.show()
        }
        panel?.close()
        panel = nil
    }

    func testUITestDriverTogglesEveryComponentFiveTimes() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(
            page: page,
            onSave: { _, _ in },
            onToggleComponent: { _ in },
            onSetAll: { _ in }
        )
        panel.show()
        let ids = UITestDriver.identifiers().filter { $0.hasPrefix("component-") && $0 != "component-list" }
        XCTAssertGreaterThanOrEqual(ids.count, 21)
        for _ in 1...5 {
            for identifier in ids {
                XCTAssertTrue(UITestDriver.clickIdentifier(identifier), identifier)
            }
        }
        panel.close()
    }

    func testClickingEveryComponentFiveTimesDoesNotCrash() {
        _ = NSApplication.shared
        let page = Self.nestedPage()
        let panel = PagePanelController(
            page: page,
            onSave: { _, _ in },
            onToggleComponent: { _ in },
            onSetAll: { _ in }
        )
        panel.show()
        let window = NSApp.windows.first { $0.title == "Edit Status Page" }
        XCTAssertNotNil(window)
        let boxes = Self.checkboxes(in: window?.contentView)
        XCTAssertGreaterThanOrEqual(boxes.count, 21)
        for _ in 1...5 {
            for box in boxes {
                box.performClick(nil)
            }
        }
        panel.close()
    }

    private static func checkboxes(in view: NSView?) -> [NSButton] {
        guard let view else { return [] }
        var found: [NSButton] = []
        if let button = view as? NSButton {
            let identifier = button.accessibilityIdentifier()
            if identifier.hasPrefix("component-") {
                found.append(button)
            }
        }
        for child in view.subviews {
            found.append(contentsOf: checkboxes(in: child))
        }
        return found
    }

    private static func nestedPage(name: String = "Box") -> WatchedPage {
        let group = ComponentStatus(
            name: "Box Web Application",
            severity: .green,
            statusText: "Operational",
            id: "g1",
            children: (1...20).map { index in
                ComponentStatus(
                    name: "Child \(index)",
                    severity: index == 1 ? .red : .green,
                    statusText: "Operational",
                    id: "c\(index)"
                )
            },
            isGroup: true
        )
        return WatchedPage(
            url: URL(string: "https://status.box.com")!,
            name: name,
            snapshot: PageSnapshot(
                name: name,
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
