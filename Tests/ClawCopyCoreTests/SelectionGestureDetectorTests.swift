import XCTest
@testable import ClawCopyCore

final class SelectionGestureDetectorTests: XCTestCase {
    private let origin = Point(x: 100, y: 100)

    func testPlainClickIsNotASelection() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: false)
        XCTAssertFalse(detector.mouseUp(at: origin, clickCount: 1))
    }

    func testTinyJitterIsNotASelection() {
        var detector = SelectionGestureDetector(dragThreshold: 4)
        detector.mouseDown(at: origin, shift: false)
        detector.mouseDragged(to: Point(x: 101, y: 101))
        XCTAssertFalse(detector.mouseUp(at: Point(x: 101, y: 101), clickCount: 1))
    }

    func testDragIsASelection() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: false)
        detector.mouseDragged(to: Point(x: 160, y: 100))
        XCTAssertTrue(detector.mouseUp(at: Point(x: 160, y: 100), clickCount: 1))
    }

    func testDragThatReturnsToStartIsStillASelection() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: false)
        detector.mouseDragged(to: Point(x: 200, y: 100))
        XCTAssertTrue(detector.mouseUp(at: origin, clickCount: 1))
    }

    func testDoubleAndTripleClickAreSelections() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: false)
        XCTAssertTrue(detector.mouseUp(at: origin, clickCount: 2))
        detector.mouseDown(at: origin, shift: false)
        XCTAssertTrue(detector.mouseUp(at: origin, clickCount: 3))
    }

    func testShiftClickExtendsSelection() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: true)
        XCTAssertTrue(detector.mouseUp(at: origin, clickCount: 1))
    }

    func testMouseUpWithoutMouseDownIsIgnored() {
        var detector = SelectionGestureDetector()
        XCTAssertFalse(detector.mouseUp(at: origin, clickCount: 2))
    }

    func testStateResetsAfterEachGesture() {
        var detector = SelectionGestureDetector()
        detector.mouseDown(at: origin, shift: true)
        _ = detector.mouseUp(at: origin, clickCount: 1)
        // The previous shift must not leak into the next plain click.
        detector.mouseDown(at: origin, shift: false)
        XCTAssertFalse(detector.mouseUp(at: origin, clickCount: 1))
    }
}
