import AppKit
import StatusCore
import XCTest
@testable import greendot

@MainActor
final class EmptyComponentMenuTests: XCTestCase {
    func testOverallStatusRowOpensPageWhenThereAreNoComponents() {
        var opened: [URL] = []
        let pageURL = URL(string: "https://status.deepseek.com")!
        let page = WatchedPage(
            url: pageURL,
            name: "DeepSeek",
            snapshot: PageSnapshot(
                name: "DeepSeek",
                url: pageURL,
                provider: .flashduty,
                overall: .green,
                components: [],
                incidents: [],
                isUnreachable: false
            )
        )
        let menu = MenuBuilder(
            handlers: StatusMenuHandlers(
                onAdd: {},
                onEdit: { _ in },
                onRemove: { _ in },
                onToggleNotifications: { _ in },
                onOpen: { opened.append($0) },
                onRefresh: {},
                onRevealConfig: {},
                onReloadConfig: {},
                onToggleLaunchAtLogin: {},
                onAbout: {},
                onQuit: {}
            )
        ).build(for: StatusMenuState(pages: [page], severity: .green, launchAtLoginEnabled: false))
        let row = menu.item(at: 0)?.submenu?.item(withTitle: "Operational")
        XCTAssertEqual(row?.isEnabled, true)
        (row?.representedObject as? TargetAction)?.invoke()
        XCTAssertEqual(opened, [pageURL])
    }
}
