import AppKit
import ClawCopyCore

/// Watches the general pasteboard and keeps a short, in-memory history of copied text, plus
/// (opt-in) a separate, briefly kept list of passwords.
///
/// macOS has no clipboard-change notification, so this polls the pasteboard's change counter
/// (a cheap integer read). Contents are only read when the counter changes.
@MainActor
final class ClipboardHistoryController {
    private static let enabledKey = "clipboardHistoryEnabled"
    private static let passwordMinutesKey = "passwordRetentionMinutes"
    private static let pollIntervalNanoseconds: UInt64 = 500_000_000
    /// A restored password is cleared from the clipboard after this long, if still there.
    private static let restoredSecretClipboardSeconds: UInt64 = 60

    /// The choices offered for keeping passwords (0 = off, the default).
    static let passwordRetentionChoices = [0, 1, 5, 15]

    private(set) var history = ClipboardHistory()
    private(set) var secrets = SecretHistory(lifetime: 0)
    var copyPolicy = CopyPolicy()
    /// While this returns true, clipboard changes are left for later (e.g. while copy-on-select
    /// is still converting a copy to Markdown), so only the final contents are recorded.
    var shouldPause: () -> Bool = { false }

    private let pasteboard = NSPasteboard.general
    private let writer = PasteboardWriter()
    private var lastChangeCount: Int
    private var pollTask: Task<Void, Never>?
    private var clearRestoredSecretTask: Task<Void, Never>?

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.passwordMinutesKey: 0])
        lastChangeCount = pasteboard.changeCount
        secrets.lifetime = TimeInterval(passwordRetentionMinutes * 60)
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                start()
            } else {
                stop()
                clear()
            }
        }
    }

    /// How long copied passwords are kept, in minutes. 0 means passwords are never kept (and
    /// never even read).
    var passwordRetentionMinutes: Int {
        get { max(0, UserDefaults.standard.integer(forKey: Self.passwordMinutesKey)) }
        set {
            UserDefaults.standard.set(max(0, newValue), forKey: Self.passwordMinutesKey)
            secrets.lifetime = TimeInterval(passwordRetentionMinutes * 60)
            if passwordRetentionMinutes == 0 { secrets.clear() }
            secrets.purgeExpired(at: Date())
        }
    }

    var keepsPasswords: Bool { passwordRetentionMinutes > 0 }

    func start() {
        guard isEnabled, pollTask == nil else { return }
        // Only record what is copied from now on, not whatever was on the clipboard before.
        lastChangeCount = pasteboard.changeCount
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.poll()
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func purgeExpiredSecrets() {
        secrets.purgeExpired(at: Date())
    }

    func clear() {
        history.clear()
        secrets.clear()
    }

    /// Puts a history entry back on the clipboard. It then moves to the top of the history.
    func restore(at index: Int) {
        guard history.entries.indices.contains(index) else { return }
        copyToClipboard(history.entries[index])
    }

    func copyToClipboard(_ text: String) {
        writer.write(text)
        poll()
    }

    /// Puts a kept password back on the clipboard, marked concealed (so other clipboard tools
    /// skip it), and clears it from the clipboard again after a minute if it's still there.
    func restoreSecret(_ entry: SecretHistory.Entry) {
        secrets.purgeExpired(at: Date())
        guard secrets.entries.contains(entry) else { return } // expired meanwhile
        writer.writeConcealed(entry.text)
        let changeCount = pasteboard.changeCount
        poll()

        clearRestoredSecretTask?.cancel()
        clearRestoredSecretTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.restoredSecretClipboardSeconds * 1_000_000_000)
            guard !Task.isCancelled, let self, self.pasteboard.changeCount == changeCount else { return }
            self.pasteboard.clearContents()
        }
    }

    private func poll() {
        if keepsPasswords { secrets.purgeExpired(at: Date()) }
        guard !shouldPause() else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let types = (pasteboard.types ?? []).map(\.rawValue)
        let frontmost = NSWorkspace.shared.frontmostApplication
        // Classify before reading the contents: secrets are only read if they will be kept.
        switch ClipboardRecordPolicy.kind(
            pasteboardTypes: types, sourceBundleID: frontmost?.bundleIdentifier, copyPolicy: copyPolicy
        ) {
        case .ignore:
            return
        case .ordinary:
            let text = pasteboard.string(forType: .string)
            guard ClipboardRecordPolicy.isRecordable(text, copyPolicy: copyPolicy), let text else { return }
            history.record(text)
        case .secret:
            guard keepsPasswords else { return }
            let text = pasteboard.string(forType: .string)
            guard ClipboardRecordPolicy.isRecordable(text, copyPolicy: copyPolicy), let text else { return }
            // A password restored from Claw Copy itself keeps its original source name.
            let ownBundle = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
            secrets.record(text, sourceName: ownBundle ? nil : frontmost?.localizedName, at: Date())
        }
    }
}
