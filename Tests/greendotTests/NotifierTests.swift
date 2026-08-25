import AppKit
import StatusCore
import UserNotifications
import XCTest
@testable import greendot

final class NotifierTests: XCTestCase {
    func testToastAttachmentColourMatchesIssueColour() {
        _ = NSApplication.shared
        for severity in [Severity.red, .yellow, .green, .grey] {
            let toast = Toast(pageName: "GitHub", body: "Major outage", severity: severity)
            let content = Notifier.content(for: toast)
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

    func testOnlyAutoDismissToastsCarryTheClearOnLaunchCategory() {
        _ = NSApplication.shared
        let green = Notifier.content(for: Toast(pageName: "GitHub", body: "Operational", severity: .green))
        XCTAssertEqual(green.categoryIdentifier, Notifier.autoDismissCategory)
        for severity in [Severity.red, .yellow, .grey] {
            let content = Notifier.content(for: Toast(pageName: "GitHub", body: "Degraded", severity: severity))
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
}
