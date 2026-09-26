import AppKit
import XCTest
@testable import greendot
import StatusCore
import TestSupport

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

    /// One click on an allowed group. Every descendant is allowed and enabled, so the
    /// click calls `RegionFilter.allowedIDs` once per descendant.
    func measureRegionFilterScan(leaves: Int) -> Double {
        let clicks = 1
        var callbackCount = 0
        let picker = ComponentPicker(
            page: Self.regionFilteredPage(leaves: leaves),
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
        guard let group = Self.componentButton(id: "us-east-1", in: container) else {
            XCTFail("benchmark could not find the region group checkbox")
            return -1
        }
        let duration = elapsedMs(iterations: clicks) {
            group.performClick(nil)
        }
        XCTAssertEqual(callbackCount, clicks)
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
        let url = testURL(host: "nested.example")
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

    static func regionFilteredPage(leaves: Int) -> WatchedPage {
        precondition(leaves > 1)
        let children = (0..<leaves).map { index -> ComponentStatus in
            let matchesRegion = index == leaves - 1
            return ComponentStatus(
                name: matchesRegion ? "EC2 (us-east-1)" : "Component \(index)",
                severity: matchesRegion ? .red : .green,
                statusText: matchesRegion ? "Major outage" : "Operational",
                id: matchesRegion ? "leaf-us-east-1" : "leaf-\(index)"
            )
        }
        let services = ComponentStatus(
            name: "us-east-1",
            severity: .red,
            statusText: "Major outage",
            id: "us-east-1",
            children: children,
            isGroup: true
        )
        let root = ComponentStatus(
            name: "Cloud",
            severity: .red,
            statusText: "Major outage",
            id: "cloud",
            children: [services],
            isGroup: true
        )
        let url = testURL(host: "region.example")
        return WatchedPage(
            url: url,
            name: "Regions",
            enabledRegions: ["us-east-1", "eu-central-1"],
            snapshot: PageSnapshot(
                name: "Regions",
                url: url,
                provider: .aws,
                overall: .red,
                components: [root],
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
        let url = testURL(host: "components.example")
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
