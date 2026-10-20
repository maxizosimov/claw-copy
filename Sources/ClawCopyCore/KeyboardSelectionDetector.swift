import Foundation

/// Decides when a keyboard selection (Shift + navigation keys) has finished.
///
/// A keyboard selection is one or more Shift + navigation key presses (arrows, Home, End,
/// Page Up, Page Down, optionally with Option or Command), finished by releasing Shift.
/// Any other key press while Shift is held (for example typing a capital letter, which
/// replaces the selection) cancels it.
///
/// Privacy: the detector only ever learns *whether* a key press was a navigation key. It never
/// sees which character was typed and keeps no record of keys, so it cannot act as a keylogger.
public struct KeyboardSelectionDetector: Sendable {
    /// macOS virtual key codes (Carbon `kVK_*`) for keys that move the text cursor.
    public static let navigationKeyCodes: Set<UInt16> = [
        123, // kVK_LeftArrow
        124, // kVK_RightArrow
        125, // kVK_DownArrow
        126, // kVK_UpArrow
        115, // kVK_Home
        119, // kVK_End
        116, // kVK_PageUp
        121, // kVK_PageDown
    ]

    public static func isNavigationKey(_ keyCode: UInt16) -> Bool {
        navigationKeyCodes.contains(keyCode)
    }

    private var shiftDown = false
    private var selecting = false

    public init() {}

    /// A key was pressed. `isNavigationKey` must be computed with `isNavigationKey(_:)`,
    /// so callers never need to pass on which key it was.
    public mutating func keyDown(isNavigationKey: Bool, shift: Bool) {
        shiftDown = shift
        selecting = shift && isNavigationKey
    }

    /// The modifier keys changed. Returns `true` when Shift was just released at the end of
    /// a keyboard selection.
    public mutating func modifiersChanged(shift: Bool) -> Bool {
        defer { shiftDown = shift }
        guard shiftDown != shift else { return false }
        if shift {
            // A fresh Shift press starts a new, still empty, selection gesture.
            selecting = false
            return false
        }
        defer { selecting = false }
        return selecting
    }
}
