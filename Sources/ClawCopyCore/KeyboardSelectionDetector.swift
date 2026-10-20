import Foundation

/// Decides when a keyboard selection has finished. Two gestures count:
///
/// - **Extend:** one or more Shift + navigation key presses (arrows, Home, End, Page Up,
///   Page Down, optionally with Option or Command), finished by releasing Shift.
/// - **Select All:** Cmd+A, finished by releasing Command.
///
/// Any other key press before the modifier is released cancels the gesture. Typing a capital
/// letter replaces a Shift selection, and Cmd+A followed by Cmd+V (Command still held) pastes
/// over the selection, so neither should touch the clipboard.
///
/// Privacy: the detector only ever learns which *kind* of key was pressed (navigation,
/// the A key, or anything else). It never sees which character was typed and keeps no
/// record of keys, so it cannot act as a keylogger.
public struct KeyboardSelectionDetector: Sendable {
    public enum KeyKind: Equatable, Sendable {
        case navigation
        case selectAll
        case other
    }

    public struct Modifiers: Equatable, Sendable {
        public var shift: Bool
        public var command: Bool
        public var option: Bool
        public var control: Bool

        public init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
            self.shift = shift
            self.command = command
            self.option = option
            self.control = control
        }
    }

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

    /// kVK_ANSI_A: the key in the QWERTY "A" position.
    public static let selectAllKeyCode: UInt16 = 0

    public static func kind(ofKeyCode keyCode: UInt16) -> KeyKind {
        if navigationKeyCodes.contains(keyCode) { return .navigation }
        if keyCode == selectAllKeyCode { return .selectAll }
        return .other
    }

    private enum Gesture {
        case extend
        case selectAll
    }

    private var pending: Gesture?

    public init() {}

    /// A key was pressed. `kind` must be computed with `kind(ofKeyCode:)`, so callers never
    /// need to pass on which key it was.
    public mutating func keyDown(_ kind: KeyKind, modifiers: Modifiers) {
        switch kind {
        case .navigation where modifiers.shift:
            pending = .extend
        case .selectAll where modifiers == Modifiers(command: true):
            pending = .selectAll
        default:
            pending = nil
        }
    }

    /// The modifier keys changed. Returns `true` when the modifier that finishes the pending
    /// gesture (Shift for Extend, Command for Select All) was just released.
    public mutating func modifiersChanged(_ modifiers: Modifiers) -> Bool {
        switch pending {
        case .extend where !modifiers.shift,
             .selectAll where !modifiers.command:
            pending = nil
            return true
        default:
            return false
        }
    }
}
