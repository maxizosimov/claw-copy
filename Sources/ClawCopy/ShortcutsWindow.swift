import AppKit
import ClawCopyCore

/// Keyboard Shortcuts window: click a shortcut, press the new keys. ⌫ removes it, ⎋ cancels.
///
/// While recording, a *local* key monitor (this window only, never other apps) reads the key's
/// position and the modifiers held. It never reads typed characters.
@MainActor
final class ShortcutsWindow: NSObject, NSWindowDelegate {
    /// Called after shortcuts change, and with `nil`/all when recording starts/ends, so global
    /// shortcuts are paused while a new one is being recorded.
    var onRecordingChanged: ((_ isRecording: Bool) -> Void)?

    private var window: NSWindow?
    private var buttons: [ShortcutAction: NSButton] = [:]
    private let message = NSTextField(labelWithString: "")
    private var recording: ShortcutAction?
    private var keyMonitor: Any?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        refreshButtons()
        message.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let width: CGFloat = 440
        let rowHeight: CGFloat = 34
        let rows = CGFloat(ShortcutAction.allCases.count)
        let height = 70 + rows * rowHeight + 56
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let hint = NSTextField(wrappingLabelWithString: "Click a shortcut, then press the new keys (with ⌘, ⌃ or ⌥). ⌫ removes it, ⎋ cancels.")
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: height - 56, width: width - 40, height: 40)
        content.addSubview(hint)

        for (index, action) in ShortcutAction.allCases.enumerated() {
            let y = height - 70 - CGFloat(index + 1) * rowHeight
            let label = NSTextField(labelWithString: action.title)
            label.frame = NSRect(x: 20, y: y + 6, width: 220, height: 20)
            content.addSubview(label)

            let button = NSButton(title: "", target: self, action: #selector(startRecording(_:)))
            button.bezelStyle = .rounded
            button.frame = NSRect(x: width - 180, y: y, width: 160, height: 30)
            button.tag = index
            content.addSubview(button)
            buttons[action] = button
        }

        message.frame = NSRect(x: 20, y: 18, width: width - 200, height: 20)
        message.textColor = .systemRed
        content.addSubview(message)

        let reset = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        reset.bezelStyle = .rounded
        reset.sizeToFit()
        reset.frame.origin = NSPoint(x: width - reset.frame.width - 20, y: 12)
        content.addSubview(reset)

        window.contentView = content
        window.center()
        return window
    }

    private func refreshButtons() {
        for (action, button) in buttons {
            if action == recording {
                button.title = "Press shortcut…"
            } else {
                button.title = ShortcutSettings.combo(for: action)?.displayString ?? "None"
            }
        }
    }

    @objc private func startRecording(_ sender: NSButton) {
        guard ShortcutAction.allCases.indices.contains(sender.tag) else { return }
        stopRecording()
        recording = ShortcutAction.allCases[sender.tag]
        message.stringValue = ""
        onRecordingChanged?(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Only the key's position and the modifiers; the event is swallowed.
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            Task { @MainActor [weak self] in
                self?.record(keyCode: keyCode, flags: flags)
            }
            return nil
        }
        refreshButtons()
    }

    private func record(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard let action = recording else { return }
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        if modifiers.isEmpty, keyCode == 53 { // ⎋
            stopRecording()
            return
        }
        if modifiers.isEmpty, keyCode == 51 || keyCode == 117 { // ⌫ / ⌦
            ShortcutSettings.set(nil, for: action)
            stopRecording()
            return
        }

        let combo = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        let others = ShortcutAction.allCases.filter { $0 != action }.compactMap(ShortcutSettings.combo(for:))
        switch KeyCombo.problem(with: combo, otherShortcuts: others) {
        case nil:
            ShortcutSettings.set(combo, for: action)
            stopRecording()
        case .needsModifier:
            message.stringValue = "Use ⌘, ⌃ or ⌥ with the key."
        case .unsupportedKey:
            message.stringValue = "That key can't be used for a shortcut."
        case .reserved:
            message.stringValue = "\(combo.displayString) is a standard Mac shortcut."
        case .duplicate:
            message.stringValue = "\(combo.displayString) is already used."
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        let wasRecording = recording != nil
        recording = nil
        refreshButtons()
        if wasRecording { onRecordingChanged?(false) }
    }

    @objc private func resetToDefaults() {
        stopRecording()
        ShortcutSettings.resetToDefaults()
        message.stringValue = ""
        refreshButtons()
        onRecordingChanged?(false)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }
}
