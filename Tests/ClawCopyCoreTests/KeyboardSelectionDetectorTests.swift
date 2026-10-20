import XCTest
@testable import ClawCopyCore

final class KeyboardSelectionDetectorTests: XCTestCase {
    private let leftArrow: UInt16 = 123
    private let letterA: UInt16 = 0

    func testShiftArrowThenReleaseIsASelection() {
        var detector = KeyboardSelectionDetector()
        XCTAssertFalse(detector.modifiersChanged(shift: true))
        detector.keyDown(isNavigationKey: true, shift: true)
        detector.keyDown(isNavigationKey: true, shift: true)
        XCTAssertTrue(detector.modifiersChanged(shift: false))
    }

    func testShiftAloneIsNotASelection() {
        var detector = KeyboardSelectionDetector()
        XCTAssertFalse(detector.modifiersChanged(shift: true))
        XCTAssertFalse(detector.modifiersChanged(shift: false))
    }

    func testArrowWithoutShiftIsNotASelection() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(isNavigationKey: true, shift: false)
        XCTAssertFalse(detector.modifiersChanged(shift: false))
    }

    func testTypingWhileShiftHeldCancelsSelection() {
        var detector = KeyboardSelectionDetector()
        _ = detector.modifiersChanged(shift: true)
        detector.keyDown(isNavigationKey: true, shift: true)
        // A capital letter replaces the selected text, so there is nothing left to copy.
        detector.keyDown(isNavigationKey: false, shift: true)
        XCTAssertFalse(detector.modifiersChanged(shift: false))
    }

    func testOtherModifierChangesWhileShiftHeldAreIgnored() {
        var detector = KeyboardSelectionDetector()
        _ = detector.modifiersChanged(shift: true)
        detector.keyDown(isNavigationKey: true, shift: true)
        // Pressing or releasing Option/Command keeps Shift down: not the end of the gesture.
        XCTAssertFalse(detector.modifiersChanged(shift: true))
        XCTAssertTrue(detector.modifiersChanged(shift: false))
    }

    func testStateResetsAfterEachSelection() {
        var detector = KeyboardSelectionDetector()
        _ = detector.modifiersChanged(shift: true)
        detector.keyDown(isNavigationKey: true, shift: true)
        XCTAssertTrue(detector.modifiersChanged(shift: false))
        // The previous selection must not leak into the next Shift press.
        XCTAssertFalse(detector.modifiersChanged(shift: true))
        XCTAssertFalse(detector.modifiersChanged(shift: false))
    }

    func testOnlyNavigationKeysAreRecognised() {
        XCTAssertTrue(KeyboardSelectionDetector.isNavigationKey(leftArrow))
        for code: UInt16 in [115, 116, 119, 121, 123, 124, 125, 126] {
            XCTAssertTrue(KeyboardSelectionDetector.isNavigationKey(code), "key code \(code)")
        }
        XCTAssertFalse(KeyboardSelectionDetector.isNavigationKey(letterA))
        XCTAssertFalse(KeyboardSelectionDetector.isNavigationKey(36)) // Return
        XCTAssertFalse(KeyboardSelectionDetector.isNavigationKey(48)) // Tab
    }
}
