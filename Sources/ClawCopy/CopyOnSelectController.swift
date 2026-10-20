import AppKit
import ClawCopyCore

/// Glues mouse gestures, the Accessibility reader, the copy policies and the pasteboard.
@MainActor
final class CopyOnSelectController {
    var copyPolicy = CopyPolicy()
    var fallbackPolicy = KeystrokeFallbackPolicy()

    private let reader = SelectionReader()
    private let pasteboard = PasteboardWriter()
    private var pending: Task<Void, Never>?

    /// Give the target app a moment to finish updating its selection after mouse-up.
    private let settleDelayNanoseconds: UInt64 = 60_000_000

    func selectionGestureEnded() {
        pending?.cancel()
        let delay = settleDelayNanoseconds
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.captureSelection()
        }
    }

    private func captureSelection() {
        guard Permissions.isTrusted(prompt: false) else { return }

        let snapshot = reader.read()
        if let own = Bundle.main.bundleIdentifier, snapshot.bundleID == own { return }

        let decision = copyPolicy.evaluate(
            text: snapshot.selectedText,
            sourceBundleID: snapshot.bundleID,
            isSecureField: snapshot.isSecureField,
            currentClipboard: pasteboard.currentString()
        )

        switch decision {
        case .copy(let text):
            pasteboard.write(text)
        case .skip(.empty):
            // The app may simply not expose its selection via Accessibility (e.g. browsers).
            if fallbackPolicy.allowsFallback(focusedRole: snapshot.role, sourceBundleID: snapshot.bundleID) {
                KeystrokeCopier.sendCopy()
            }
        case .skip:
            break
        }
    }
}
