import XCTest
@testable import TowerIsland

@MainActor
final class NotchWindowTests: XCTestCase {
    func testCollapsedWindowFrameMatchesVisiblePillSize() {
        let window = NotchWindow()

        window.resizeToFitCollapse(contentWidth: 180, contentHeight: 32)

        XCTAssertEqual(window.frame.width, 180, accuracy: 0.5)
        XCTAssertEqual(window.frame.height, 32, accuracy: 0.5)
    }
}
