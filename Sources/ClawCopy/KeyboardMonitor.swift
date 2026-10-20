import AppKit
import ClawCopyCore

/// Watches the keyboard system-wide (passively; events are never modified or blocked) and
/// reports when a Shift + navigation key selection has finished.
///
/// Privacy: each key press is reduced on the spot to "was it a navigation key, and was Shift
/// held". The typed characters are never read, and nothing about other keys is stored.
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
            let isKeyDown = event.type == .keyDown
            let isNavigationKey = isKeyDown && KeyboardSelectionDetector.isNavigationKey(event.keyCode)
            let shift = event.modifierFlags.contains(.shift)
            Task { @MainActor [weak self] in
                self?.handle(isKeyDown: isKeyDown, isNavigationKey: isNavigationKey, shift: shift)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(isKeyDown: Bool, isNavigationKey: Bool, shift: Bool) {
        if isKeyDown {
            detector.keyDown(isNavigationKey: isNavigationKey, shift: shift)
        } else if detector.modifiersChanged(shift: shift) {
            onSelectionGesture?()
        }
    }
}
