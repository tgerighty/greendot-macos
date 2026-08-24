import AppKit
import StatusCore
import UserNotifications
import XCTest
@testable import greendot

final class NotifierTests: XCTestCase {
    func testToastIconColourMatchesIssueColour() {
        _ = NSApplication.shared
        for severity in [Severity.red, .yellow, .green, .grey] {
            let toast = Toast(pageName: "GitHub", body: "Major outage", severity: severity)
            let content = Notifier.content(for: toast)
            XCTAssertEqual(content.title, "GitHub")
            XCTAssertEqual(content.body, "Major outage")
            guard let png = Self.iconPNG(content),
                  let sampled = Self.centerColor(png) else {
                XCTFail("missing toast icon for \(severity.rawValue)")
                continue
            }
            XCTAssertEqual(
                Self.nearestSeverity(to: sampled),
                severity,
                "toast icon for \(severity.rawValue) sampled \(sampled)"
            )
        }
    }

    private static func iconPNG(_ content: UNMutableNotificationContent) -> Data? {
        guard let icon = content.value(forKey: "icon") as? NSObject else { return nil }
        return icon.perform(NSSelectorFromString("data"))?.takeUnretainedValue() as? Data
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
