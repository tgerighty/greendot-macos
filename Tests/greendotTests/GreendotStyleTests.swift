import XCTest
@testable import greendot

final class GreendotStyleTests: XCTestCase {
    func testDarkChromeKeepsStatusColoursAndDarkensThePanel() {
        _ = NSApplication.shared
        guard let light = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua) else {
            return XCTFail("The system appearances are missing.")
        }
        let lightBg = GreendotStyle.palette(matching: light).background.usingColorSpace(.sRGB)
        let darkBg = GreendotStyle.palette(matching: dark).background.usingColorSpace(.sRGB)
        XCTAssertGreaterThan(lightBg?.brightnessComponent ?? 0, darkBg?.brightnessComponent ?? 1)
        let lightGrey = GreendotStyle.concrete(.grey, darkChrome: false).usingColorSpace(.sRGB)
        let darkGrey = GreendotStyle.concrete(.grey, darkChrome: true).usingColorSpace(.sRGB)
        XCTAssertGreaterThan(darkGrey?.brightnessComponent ?? 0, lightGrey?.brightnessComponent ?? 1)
        let green = GreendotStyle.concrete(.green, darkChrome: true).usingColorSpace(.sRGB)
        XCTAssertEqual(green?.greenComponent ?? 0, 0.5552, accuracy: 0.01)
    }
}
