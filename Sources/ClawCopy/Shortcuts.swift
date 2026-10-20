import AppKit
import Carbon.HIToolbox
import ClawCopyCore

/// The user's keyboard shortcuts, stored in UserDefaults. A missing value means "use the
/// default"; an empty string means the user removed the shortcut.
@MainActor
enum ShortcutSettings {
    private static func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

    static func combo(for action: ShortcutAction) -> KeyCombo? {
        guard let stored = UserDefaults.standard.string(forKey: key(action)) else { return action.defaultCombo }
        return KeyCombo(storageString: stored)
    }

    static func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        UserDefaults.standard.set(combo?.storageString ?? "", forKey: key(action))
    }

    static func resetToDefaults() {
        for action in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: key(action))
        }
    }

    static var all: [ShortcutAction: KeyCombo] {
        var result: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            if let combo = combo(for: action) { result[action] = combo }
        }
        return result
    }
}

/// Global shortcuts via the Carbon hot key API (`RegisterEventHotKey`). macOS delivers only the
/// exact registered key combinations to the app; no other key presses are seen, and no event
/// tap or Accessibility access is involved.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onAction: ((ShortcutAction) -> Void)?

    private static let signature: OSType = 0x434C_4157 // "CLAW"
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: ShortcutAction] = [:]
    private var handler: EventHandlerRef?

    /// Replaces all registered shortcuts with `shortcuts`.
    func register(_ shortcuts: [ShortcutAction: KeyCombo]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = shortcuts[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(combo.keyCode),
                Self.carbonModifiers(combo.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeys[id] = ref
                actions[id] = action
            }
        }
    }

    func unregisterAll() {
        for ref in hotKeys.values {
            UnregisterEventHotKey(ref)
        }
        hotKeys = [:]
        actions = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            Task { @MainActor in
                HotKeyCenter.shared.fire(id)
            }
            return noErr
        }, 1, &eventType, nil, &handler)
    }

    private func fire(_ id: UInt32) {
        if let action = actions[id] {
            onAction?(action)
        }
    }

    private static func carbonModifiers(_ modifiers: KeyCombo.Modifiers) -> UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
