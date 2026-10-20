import Foundation

/// A keyboard shortcut: a physical key (macOS virtual key code) plus modifier keys.
///
/// Keys are identified by position (key code), never by the character they type, so recording
/// and showing shortcuts never involves reading typed text. Labels follow the US layout.
public struct KeyCombo: Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// e.g. "⌃⌥⌘V", in macOS's standard modifier order.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    // MARK: Validation

    public enum Problem: Equatable, Sendable {
        /// Needs ⌘, ⌃ or ⌥, so a global shortcut never swallows ordinary typing.
        case needsModifier
        /// A key this app doesn't offer as a shortcut key.
        case unsupportedKey
        /// A shortcut macOS or nearly every app already uses (e.g. ⌘Q, ⌘C).
        case reserved
        /// Already used by another Claw Copy action.
        case duplicate
    }

    public static func problem(with combo: KeyCombo, otherShortcuts: [KeyCombo]) -> Problem? {
        guard keyNames[combo.keyCode] != nil else { return .unsupportedKey }
        guard !combo.modifiers.intersection([.command, .control, .option]).isEmpty else { return .needsModifier }
        if reserved.contains(combo) { return .reserved }
        if otherShortcuts.contains(combo) { return .duplicate }
        return nil
    }

    /// ⌘ + these keys are standard app commands (Quit, Copy, Paste, Tab switching, …).
    private static let reserved: Set<KeyCombo> = {
        // Q W E R T A S D F Z X C V B N H M O P , . Tab Space `
        let commandKeys: [UInt16] = [12, 13, 14, 15, 17, 0, 1, 2, 3, 6, 7, 8, 9, 11, 45, 4, 46, 31, 35, 43, 47, 48, 49, 50]
        var combos = Set(commandKeys.map { KeyCombo(keyCode: $0, modifiers: .command) })
        combos.formUnion(commandKeys.map { KeyCombo(keyCode: $0, modifiers: [.command, .shift]) })
        combos.insert(KeyCombo(keyCode: 49, modifiers: .control)) // ⌃Space: input sources
        combos.insert(KeyCombo(keyCode: 12, modifiers: [.command, .option])) // ⌥⌘Q
        combos.insert(KeyCombo(keyCode: 53, modifiers: [.command, .option])) // ⌥⌘Esc: Force Quit
        return combos
    }()

    // MARK: Storage

    /// Compact form for UserDefaults: "keyCode:modifiers".
    public var storageString: String { "\(keyCode):\(modifiers.rawValue)" }

    public init?(storageString: String) {
        let parts = storageString.split(separator: ":")
        guard parts.count == 2, let code = UInt16(parts[0]), let mods = UInt8(parts[1]),
              Self.keyNames[code] != nil else { return nil }
        self.init(keyCode: code, modifiers: Modifiers(rawValue: mods))
    }

    // MARK: Key names (US layout, by key position)

    public static let keyNames: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 50: "`",
        49: "Space", 48: "⇥", 36: "↩", 53: "⎋", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]
}

/// The app's keyboard shortcuts and their defaults.
public enum ShortcutAction: String, CaseIterable, Sendable {
    case openMenu
    case showHistory
    case switchCopyMode

    public var title: String {
        switch self {
        case .openMenu: return "Open Claw Copy Menu"
        case .showHistory: return "Show Clipboard History"
        case .switchCopyMode: return "Switch Copy Mode"
        }
    }

    /// ⌃⌥⌘ + a letter: rarely used by other apps.
    public var defaultCombo: KeyCombo {
        let hyper: KeyCombo.Modifiers = [.control, .option, .command]
        switch self {
        case .openMenu: return KeyCombo(keyCode: 8, modifiers: hyper)        // C
        case .showHistory: return KeyCombo(keyCode: 9, modifiers: hyper)     // V
        case .switchCopyMode: return KeyCombo(keyCode: 46, modifiers: hyper) // M
        }
    }
}
