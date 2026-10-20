import AppKit
import ClawCopyCore

/// Glues mouse gestures, the Accessibility reader, the copy policies and the pasteboard.
@MainActor
final class CopyOnSelectController {
    private static let modeKey = "copyMode"

    var copyPolicy = CopyPolicy()
    var fallbackPolicy = KeystrokeFallbackPolicy()

    /// True while a Markdown conversion is waiting for, or rewriting, the app's copy. Clipboard
    /// history pauses meanwhile so it records only the final Markdown.
    private(set) var isConvertingClipboard = false

    private let reader = SelectionReader()
    private let pasteboard = PasteboardWriter()
    private var pending: Task<Void, Never>?

    /// Give the target app a moment to finish updating its selection after mouse-up.
    private let settleDelayNanoseconds: UInt64 = 60_000_000

    var mode: CopyMode {
        get { CopyMode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .plainText }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    func selectionGestureEnded() {
        pending?.cancel()
        let delay = settleDelayNanoseconds
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.captureSelection()
        }
    }

    private func captureSelection() async {
        guard Permissions.isTrusted(prompt: false) else { return }

        let snapshot = reader.read()
        if let own = Bundle.main.bundleIdentifier, snapshot.bundleID == own { return }

        let decision = copyPolicy.evaluate(
            text: snapshot.selectedText,
            sourceBundleID: snapshot.bundleID,
            isSecureField: snapshot.isSecureField,
            currentClipboard: pasteboard.currentString()
        )
        let mode = self.mode
        let action = CapturePlanner.plan(
            decision: decision,
            mode: mode,
            fallbackAllowed: fallbackPolicy.allowsFallback(focusedRole: snapshot.role, sourceBundleID: snapshot.bundleID)
        )

        switch action {
        case .none:
            break
        case .writePlain(let text):
            pasteboard.write(text)
        case .sendCopyKeystroke:
            // Cmd+C goes to whichever app is frontmost when it is sent. Only send it if that is
            // still the app the selection came from (the user may have switched apps, e.g.
            // to a password manager, since the selection was read).
            guard isStillFrontmost(snapshot.bundleID) else { return }
            if mode == .markdown {
                await copyAsMarkdown()
            } else {
                KeystrokeCopier.sendCopy()
            }
        }
    }

    private func isStillFrontmost(_ bundleID: String?) -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return frontmost == bundleID && !copyPolicy.isExcluded(bundleID: frontmost)
    }

    /// Sends Cmd+C, waits for the app's copy, and replaces its HTML with Markdown. If the app
    /// copied no HTML (or it can't be converted), its copy is left exactly as it is.
    private func copyAsMarkdown() async {
        isConvertingClipboard = true
        defer { isConvertingClipboard = false }

        let before = pasteboard.changeCount
        KeystrokeCopier.sendCopy()
        for _ in 0..<30 where pasteboard.changeCount == before {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        guard pasteboard.changeCount != before else { return }
        // The app clears the pasteboard first and then writes its types; let it finish.
        try? await Task.sleep(nanoseconds: 30_000_000)

        // Never touch concealed/transient copies (password managers).
        guard !pasteboard.types.contains(where: ClipboardRecordPolicy.privateTypes.contains),
              let html = pasteboard.currentHTML(),
              let markdown = HTMLToMarkdown.convert(html) else { return }
        pasteboard.writeMarkdown(markdown)
    }
}
