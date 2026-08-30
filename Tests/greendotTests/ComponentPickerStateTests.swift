import AppKit
import StatusCore
import TestSupport
import XCTest
@testable import greendot

@MainActor
final class ComponentPickerStateTests: XCTestCase {
    func testInitialStatesAreOnWhenEveryComponentIsEnabled() throws {
        let (_, view) = installPicker(page: Self.page())

        for identifier in ["all", "root", "login", "search"] {
            let button = try XCTUnwrap(Self.button(identifier, in: view))
            XCTAssertEqual(button.state, .on)
            XCTAssertFalse(button.allowsMixedState)
        }
    }

    func testInitialStatesHonorDisabledIDAndName() throws {
        let (_, view) = installPicker(page: Self.page(disabledKeys: ["login", "Search"]))

        XCTAssertEqual(try Self.state("login", in: view), .off)
        XCTAssertEqual(try Self.state("search", in: view), .off)
        XCTAssertEqual(try Self.state("root", in: view), .mixed)
        XCTAssertEqual(try Self.state("all", in: view), .mixed)
    }

    func testSuccessfulRootClickTurnsTheWholeTreeOff() throws {
        var toggledKey: String?
        let (picker, view) = installPicker(
            page: Self.page(),
            onToggleComponent: {
                toggledKey = $0
                return true
            }
        )
        defer { _ = picker }

        try XCTUnwrap(Self.button("root", in: view)).performClick(nil)

        XCTAssertEqual(toggledKey, "root")
        for identifier in ["all", "root", "login", "search"] {
            XCTAssertEqual(try Self.state(identifier, in: view), .off)
        }
    }

    func testRejectedChildClickRestoresTheSavedState() throws {
        var toggledKey: String?
        let (picker, view) = installPicker(
            page: Self.page(),
            onToggleComponent: {
                toggledKey = $0
                return false
            }
        )
        defer { _ = picker }

        try XCTUnwrap(Self.button("login", in: view)).performClick(nil)

        XCTAssertEqual(toggledKey, "login")
        for identifier in ["all", "root", "login", "search"] {
            XCTAssertEqual(try Self.state(identifier, in: view), .on)
        }
    }

    func testSuccessfulAllClickTurnsEveryComponentOff() throws {
        var requestedState: Bool?
        let (picker, view) = installPicker(
            page: Self.page(),
            onSetAll: {
                requestedState = $0
                return true
            }
        )
        defer { _ = picker }

        try XCTUnwrap(Self.button("all", in: view)).performClick(nil)

        XCTAssertEqual(requestedState, false)
        for identifier in ["all", "root", "login", "search"] {
            XCTAssertEqual(try Self.state(identifier, in: view), .off)
        }
    }

    func testDuplicateIDUsesTheLastCheckboxSubtreeState() throws {
        let duplicateLeaf = ComponentStatus(
            name: "Duplicate leaf",
            severity: .green,
            statusText: "Operational",
            id: "duplicate"
        )
        let root = ComponentStatus(
            name: "Duplicate root",
            severity: .green,
            statusText: "Operational",
            id: "duplicate",
            children: [
                ComponentStatus(name: "Unique", severity: .green, statusText: "Operational", id: "unique"),
                duplicateLeaf
            ],
            isGroup: true
        )
        let page = Self.page(components: [root], disabledKeys: ["duplicate"])
        let (picker, view) = installPicker(page: page)
        defer { _ = picker }

        let duplicateButtons = Self.buttons("duplicate", in: view)
        let leafButton = try XCTUnwrap(duplicateButtons.first { $0.title.contains("Duplicate leaf") })
        XCTAssertEqual(duplicateButtons.count, 2)
        XCTAssertEqual(leafButton.state, .off)
        XCTAssertFalse(leafButton.allowsMixedState)
        XCTAssertEqual(try Self.state("all", in: view), .mixed)
    }

    private func installPicker(
        page: WatchedPage,
        onToggleComponent: @escaping (String) -> Bool = { _ in true },
        onSetAll: @escaping (Bool) -> Bool = { _ in true }
    ) -> (ComponentPicker, NSView) {
        let picker = ComponentPicker(
            page: page,
            onToggleComponent: onToggleComponent,
            onSetAll: onSetAll
        )
        let view = NSView()
        let anchor = NSView()
        view.addSubview(anchor)
        _ = picker.install(in: view, below: anchor, listHeight: 200)
        return (picker, view)
    }

    private static func page(disabledKeys: Set<String> = []) -> WatchedPage {
        let root = ComponentStatus(
            name: "Root",
            severity: .green,
            statusText: "Operational",
            id: "root",
            children: [
                ComponentStatus(name: "Login", severity: .green, statusText: "Operational", id: "login"),
                ComponentStatus(name: "Search", severity: .green, statusText: "Operational", id: "search")
            ],
            isGroup: true
        )
        return page(components: [root], disabledKeys: disabledKeys)
    }

    private static func page(
        components: [ComponentStatus],
        disabledKeys: Set<String>
    ) -> WatchedPage {
        let url = testURL(host: "picker.example")
        return WatchedPage(
            url: url,
            name: "Picker",
            disabledComponentNames: disabledKeys,
            snapshot: PageSnapshot(
                name: "Picker",
                url: url,
                provider: .statuspage,
                overall: .green,
                components: components,
                incidents: [],
                isUnreachable: false
            )
        )
    }

    private static func state(_ identifier: String, in view: NSView) throws -> NSControl.StateValue {
        try XCTUnwrap(button(identifier, in: view)).state
    }

    private static func button(_ identifier: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton {
            if identifier == "all", button.accessibilityIdentifier() == "component-all" {
                return button
            }
            if button.identifier?.rawValue == identifier {
                return button
            }
        }
        for child in view.subviews {
            if let match = button(identifier, in: child) {
                return match
            }
        }
        return nil
    }

    private static func buttons(_ identifier: String, in view: NSView) -> [NSButton] {
        var matches: [NSButton] = []
        if let button = view as? NSButton,
           button.identifier?.rawValue == identifier {
            matches.append(button)
        }
        for child in view.subviews {
            matches.append(contentsOf: buttons(identifier, in: child))
        }
        return matches
    }
}
