import AppKit
import ApplicationServices

enum Permissions {
    /// Whether macOS has granted this app Accessibility access, which is required both to
    /// read the selected text of other apps and to send the Cmd+C fallback keystroke.
    static func isTrusted(prompt: Bool) -> Bool {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings › Privacy & Security › Accessibility. This is a local
    /// `x-apple.systempreferences:` URL handled by macOS itself; no network is involved.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
