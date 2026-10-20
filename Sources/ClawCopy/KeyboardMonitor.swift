import AppKit
import ClawCopyCore

/// Watches the keyboard system-wide (passively; events are never modified or blocked) and
/// reports when a keyboard selection (Shift + navigation keys, or Cmd+A) has finished.
///
/// Privacy: each key press is reduced on the spot to its kind (navigation key, the A key, or
/// anything else) and which modifiers were held. The typed characters are never read, and nothing about other keys is stored.
/// macOS also stops delivering key events to monitors while a password field has focus
/// (Secure Event Input).
@MainActor
final class KeyboardMonitor {
    var onSelectionGesture: (() -> Void)?

    private var detector = KeyboardSelectionDetector()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Extract plain values here; hop to the main actor to update state.
            let kind: KeyboardSelectionDetector.KeyKind? = event.type == .keyDown
                ? KeyboardSelectionDetector.kind(ofKeyCode: event.keyCode)
                : nil
            let flags = event.modifierFlags
            let modifiers = KeyboardSelectionDetector.Modifiers(
                shift: flags.contains(.shift),
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )
            Task { @MainActor [weak self] in
                self?.handle(kind: kind, modifiers: modifiers)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(kind: KeyboardSelectionDetector.KeyKind?, modifiers: KeyboardSelectionDetector.Modifiers) {
        if let kind {
            detector.keyDown(kind, modifiers: modifiers)
        } else if detector.modifiersChanged(modifiers) {
            onSelectionGesture?()
        }
    }
}
