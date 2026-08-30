import AppKit
import XCTest
@testable import greendot
import StatusCore

extension PerformanceHarnessTests {
    func measureComponentPickerClick(depth: Int) -> Double {
        var callbackCount = 0
        let picker = ComponentPicker(
            page: Self.deeplyNestedPage(depth: depth),
            onToggleComponent: { _ in
                callbackCount += 1
                return true
            },
            onSetAll: { _ in true }
        )
        let container = NSView()
        let anchor = NSView()
        container.addSubview(anchor)
        _ = picker.install(in: container, below: anchor, listHeight: 296)
        guard let root = Self.componentButton(id: "deep-0", in: container) else {
            XCTFail("benchmark could not find the root component checkbox")
            return -1
        }
        let duration = elapsedMs(iterations: 20) {
            root.performClick(nil)
        }
        XCTAssertEqual(callbackCount, 20)
        return duration
    }

    func measureDisplaySeverity() -> Double {
        let page = Self.componentRichPage(groups: 40, childrenPerGroup: 20)
        var redCount = 0
        let duration = elapsedMs(iterations: 500) {
            if page.displaySeverity == .red {
                redCount += 1
            }
        }
        XCTAssertEqual(redCount, 500)
        return duration
    }

    static func deeplyNestedPage(depth: Int) -> WatchedPage {
        precondition(depth > 0)
        var component = ComponentStatus(
            name: "Component \(depth - 1)",
            severity: .green,
            statusText: "Operational",
            id: "deep-\(depth - 1)"
        )
        for index in (0..<(depth - 1)).reversed() {
            component = ComponentStatus(
                name: "Component \(index)",
                severity: .green,
                statusText: "Operational",
                id: "deep-\(index)",
                children: [component],
                isGroup: true
            )
        }
        let url = URL(string: "https://nested.example")!
        return WatchedPage(
            url: url,
            name: "Nested",
            snapshot: PageSnapshot(
                name: "Nested",
                url: url,
                provider: .statuspal,
                overall: .green,
                components: [component],
                incidents: [],
                isUnreachable: false
            )
        )
    }

    static func componentRichPage(groups: Int, childrenPerGroup: Int) -> WatchedPage {
        let components = (0..<groups).map { groupIndex in
            ComponentStatus(
                name: "Group \(groupIndex)",
                severity: .green,
                statusText: "Operational",
                id: "group-\(groupIndex)",
                children: (0..<childrenPerGroup).map { childIndex in
                    let isLast = groupIndex == groups - 1 && childIndex == childrenPerGroup - 1
                    return ComponentStatus(
                        name: "Component \(groupIndex)-\(childIndex)",
                        severity: isLast ? .red : .green,
                        statusText: isLast ? "Major outage" : "Operational",
                        id: "component-\(groupIndex)-\(childIndex)"
                    )
                },
                isGroup: true
            )
        }
        let url = URL(string: "https://components.example")!
        return WatchedPage(
            url: url,
            name: "Components",
            snapshot: PageSnapshot(
                name: "Components",
                url: url,
                provider: .statuspage,
                overall: .red,
                components: components,
                incidents: [],
                isUnreachable: false
            )
        )
    }

    static func componentButton(id: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.identifier?.rawValue == id {
            return button
        }
        for child in view.subviews {
            if let match = componentButton(id: id, in: child) {
                return match
            }
        }
        return nil
    }
}
