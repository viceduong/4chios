import SwiftUI
import XCTest
@testable import ChanUI

final class ChanThemeTests: XCTestCase {
    func testThemesAreDistinct() {
        XCTAssertNotEqual(ChanTheme.light.background, ChanTheme.dark.background)
        XCTAssertNotEqual(ChanTheme.dark.background, ChanTheme.oled.background)
    }

    func testOledBackgroundIsPureBlack() {
        XCTAssertEqual(ChanTheme.oled.background, Color(chanHex: 0x000000))
    }

    func testSpacingScaleIsMonotonic() {
        XCTAssertLessThan(ChanSpacing.xs, ChanSpacing.s)
        XCTAssertLessThan(ChanSpacing.s, ChanSpacing.m)
        XCTAssertLessThan(ChanSpacing.m, ChanSpacing.l)
        XCTAssertLessThan(ChanSpacing.l, ChanSpacing.xl)
    }
}
