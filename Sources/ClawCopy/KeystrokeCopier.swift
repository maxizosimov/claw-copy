import AppKit
import Carbon.HIToolbox

/// Sends the frontmost app a standard Cmd+C. Used only as a fallback for apps that do not
/// expose their selection through the Accessibility API (see KeystrokeFallbackPolicy).
enum KeystrokeCopier {
    static func sendCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_C)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            return
        }
        // Exactly Cmd, regardless of which modifiers the user is physically holding.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
