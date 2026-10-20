import XCTest
@testable import ClawCopyCore

final class KeyboardSelectionDetectorTests: XCTestCase {
    private typealias Modifiers = KeyboardSelectionDetector.Modifiers
    private let none = Modifiers()
    private let shift = Modifiers(shift: true)
    private let command = Modifiers(command: true)

    // MARK: Shift + navigation

    func testShiftArrowThenReleaseIsASelection() {
        var detector = KeyboardSelectionDetector()
        XCTAssertFalse(detector.modifiersChanged(shift))
        detector.keyDown(.navigation, modifiers: shift)
        detector.keyDown(.navigation, modifiers: shift)
        XCTAssertTrue(detector.modifiersChanged(none))
    }

    func testShiftAloneIsNotASelection() {
        var detector = KeyboardSelectionDetector()
        XCTAssertFalse(detector.modifiersChanged(shift))
        XCTAssertFalse(detector.modifiersChanged(none))
    }

    func testArrowWithoutShiftIsNotASelection() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(.navigation, modifiers: none)
        XCTAssertFalse(detector.modifiersChanged(none))
    }

    func testTypingWhileShiftHeldCancelsSelection() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(.navigation, modifiers: shift)
        // A capital letter replaces the selected text, so there is nothing left to copy.
        detector.keyDown(.other, modifiers: shift)
        XCTAssertFalse(detector.modifiersChanged(none))
    }

    func testOtherModifierChangesWhileShiftHeldAreIgnored() {
        var detector = KeyboardSelectionDetector()
        let shiftCommand = Modifiers(shift: true, command: true)
        detector.keyDown(.navigation, modifiers: shiftCommand)
        // Releasing Command first keeps Shift down: not the end of the gesture.
        XCTAssertFalse(detector.modifiersChanged(shift))
        XCTAssertTrue(detector.modifiersChanged(none))
    }

    // MARK: Cmd+A

    func testSelectAllThenReleaseCommandIsASelection() {
        var detector = KeyboardSelectionDetector()
        XCTAssertFalse(detector.modifiersChanged(command))
        detector.keyDown(.selectAll, modifiers: command)
        XCTAssertTrue(detector.modifiersChanged(none))
    }

    func testSelectAllThenPasteWithCommandHeldIsNotASelection() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(.selectAll, modifiers: command)
        // Cmd+V replaces the selection: the clipboard must not be overwritten first.
        detector.keyDown(.other, modifiers: command)
        XCTAssertFalse(detector.modifiersChanged(none))
    }

    func testAKeyWithOtherModifiersIsNotSelectAll() {
        for modifiers in [none, shift, Modifiers(shift: true, command: true),
                          Modifiers(command: true, option: true), Modifiers(command: true, control: true)] {
            var detector = KeyboardSelectionDetector()
            detector.keyDown(.selectAll, modifiers: modifiers)
            XCTAssertFalse(detector.modifiersChanged(none), "\(modifiers)")
        }
    }

    func testReleasingShiftDoesNotFinishSelectAll() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(.selectAll, modifiers: command)
        XCTAssertFalse(detector.modifiersChanged(Modifiers(shift: true, command: true)))
        XCTAssertFalse(detector.modifiersChanged(command))
        XCTAssertTrue(detector.modifiersChanged(none))
    }

    // MARK: General

    func testStateResetsAfterEachSelection() {
        var detector = KeyboardSelectionDetector()
        detector.keyDown(.navigation, modifiers: shift)
        XCTAssertTrue(detector.modifiersChanged(none))
        // The previous selection must not leak into the next Shift press.
        XCTAssertFalse(detector.modifiersChanged(shift))
        XCTAssertFalse(detector.modifiersChanged(none))
    }

    func testKeyKinds() {
        for code: UInt16 in [115, 116, 119, 121, 123, 124, 125, 126] {
            XCTAssertEqual(KeyboardSelectionDetector.kind(ofKeyCode: code), .navigation, "key code \(code)")
        }
        XCTAssertEqual(KeyboardSelectionDetector.kind(ofKeyCode: 0), .selectAll)  // A
        XCTAssertEqual(KeyboardSelectionDetector.kind(ofKeyCode: 9), .other)      // V
        XCTAssertEqual(KeyboardSelectionDetector.kind(ofKeyCode: 8), .other)      // C
        XCTAssertEqual(KeyboardSelectionDetector.kind(ofKeyCode: 36), .other)     // Return
    }
}
