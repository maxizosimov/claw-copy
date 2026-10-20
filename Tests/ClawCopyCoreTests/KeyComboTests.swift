import XCTest
@testable import ClawCopyCore

final class KeyComboTests: XCTestCase {
    private let hyper: KeyCombo.Modifiers = [.control, .option, .command]

    func testDisplayStringUsesStandardModifierOrder() {
        XCTAssertEqual(KeyCombo(keyCode: 9, modifiers: [.command, .shift, .option, .control]).displayString, "⌃⌥⇧⌘V")
        XCTAssertEqual(KeyCombo(keyCode: 122, modifiers: .option).displayString, "⌥F1")
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: hyper).displayString, "⌃⌥⌘Space")
    }

    func testDefaults() {
        XCTAssertEqual(ShortcutAction.openMenu.defaultCombo.displayString, "⌃⌥⌘C")
        XCTAssertEqual(ShortcutAction.showHistory.defaultCombo.displayString, "⌃⌥⌘V")
        XCTAssertEqual(ShortcutAction.switchCopyMode.defaultCombo.displayString, "⌃⌥⌘M")
        let defaults = ShortcutAction.allCases.map(\.defaultCombo)
        XCTAssertEqual(Set(defaults).count, defaults.count)
        for combo in defaults {
            XCTAssertNil(KeyCombo.problem(with: combo, otherShortcuts: []))
        }
    }

    func testRequiresCommandControlOrOption() {
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 9, modifiers: []), otherShortcuts: []), .needsModifier)
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 9, modifiers: .shift), otherShortcuts: []), .needsModifier)
        XCTAssertNil(KeyCombo.problem(with: KeyCombo(keyCode: 9, modifiers: [.option, .shift]), otherShortcuts: []))
    }

    func testRejectsReservedAndDuplicateShortcuts() {
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 12, modifiers: .command), otherShortcuts: []), .reserved)   // ⌘Q
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 8, modifiers: .command), otherShortcuts: []), .reserved)    // ⌘C
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 48, modifiers: .command), otherShortcuts: []), .reserved)   // ⌘Tab
        let taken = KeyCombo(keyCode: 9, modifiers: hyper)
        XCTAssertEqual(KeyCombo.problem(with: taken, otherShortcuts: [taken]), .duplicate)
    }

    func testRejectsUnknownKeys() {
        XCTAssertEqual(KeyCombo.problem(with: KeyCombo(keyCode: 200, modifiers: hyper), otherShortcuts: []), .unsupportedKey)
    }

    func testStorageRoundTrip() {
        let combo = KeyCombo(keyCode: 46, modifiers: hyper)
        XCTAssertEqual(KeyCombo(storageString: combo.storageString), combo)
        XCTAssertNil(KeyCombo(storageString: "nonsense"))
        XCTAssertNil(KeyCombo(storageString: "999:1"))
    }
}
