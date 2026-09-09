import XCTest
@testable import ChanCore

final class MediaKindTests: XCTestCase {
    func testExtensionMapping() {
        XCTAssertEqual(MediaKind(ext: ".jpg"), .image)
        XCTAssertEqual(MediaKind(ext: "png"), .image)
        XCTAssertEqual(MediaKind(ext: ".gif"), .gif)
        XCTAssertEqual(MediaKind(ext: ".webm"), .video)
        XCTAssertEqual(MediaKind(ext: ".mp4"), .video)
        XCTAssertEqual(MediaKind(ext: ".pdf"), .pdf)
        XCTAssertEqual(MediaKind(ext: ".swf"), .flash)
        XCTAssertEqual(MediaKind(ext: ".xyz"), .other)
    }

    func testCapabilityFlags() {
        XCTAssertTrue(MediaKind.video.requiresPlaybackEngine)
        XCTAssertFalse(MediaKind.image.requiresPlaybackEngine)
        XCTAssertTrue(MediaKind.gif.isAnimated)
        XCTAssertFalse(MediaKind.image.isAnimated)
    }
}
