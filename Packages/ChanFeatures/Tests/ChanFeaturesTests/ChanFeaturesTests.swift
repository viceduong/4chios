import ChanCore
import ChanUI
import XCTest
@testable import ChanFeatures

final class ChanFeaturesTests: XCTestCase {
    func testFeatureLayerLinksCoreAndUI() {
        // Guards the module graph: the feature layer must see both the domain
        // types and the design system.
        XCTAssertEqual(ChanVersion.current, "0.1.0")
        XCTAssertEqual(ChanTheme.dark.accent, ChanTheme.dark.accent)
    }
}
