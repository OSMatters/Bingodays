import XCTest
@testable import Bingodays

final class BlindBoxCanvasLayoutTests: XCTestCase {
    func testPhoneReferenceCanvasKeepsItsOriginalScale() {
        let metrics = BlindBoxCanvasLayout.metrics(in: CGSize(width: 393, height: 852))

        XCTAssertEqual(metrics.scale, 1, accuracy: 0.000_001)
        XCTAssertEqual(metrics.canvasSize, BlindBoxCanvasLayout.referenceSize)
        XCTAssertEqual(metrics.origin, .zero)
    }

    func testIPadPortraitCanvasIsCenteredAndFullyVisible() {
        let container = CGSize(width: 834, height: 1_194)
        let metrics = BlindBoxCanvasLayout.metrics(in: container)

        XCTAssertEqual(metrics.scale, container.height / BlindBoxCanvasLayout.referenceSize.height, accuracy: 0.000_001)
        XCTAssertEqual(metrics.canvasSize.height, container.height, accuracy: 0.000_001)
        XCTAssertEqual(metrics.origin.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(metrics.origin.x, (container.width - metrics.canvasSize.width) / 2, accuracy: 0.000_001)
    }

    func testIPadLandscapeCanvasIsCenteredAndFullyVisible() {
        let container = CGSize(width: 1_194, height: 834)
        let metrics = BlindBoxCanvasLayout.metrics(in: container)

        XCTAssertEqual(metrics.scale, container.height / BlindBoxCanvasLayout.referenceSize.height, accuracy: 0.000_001)
        XCTAssertEqual(metrics.canvasSize.height, container.height, accuracy: 0.000_001)
        XCTAssertEqual(metrics.origin.x, (container.width - metrics.canvasSize.width) / 2, accuracy: 0.000_001)
        XCTAssertEqual(metrics.origin.y, 0, accuracy: 0.000_001)
    }
}
