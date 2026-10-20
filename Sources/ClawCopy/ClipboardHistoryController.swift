import AppKit
import ClawCopyCore

/// Watches the general pasteboard and keeps a short, in-memory history of copied text.
///
/// macOS has no clipboard-change notification, so this polls the pasteboard's change counter
/// (a cheap integer read). Contents are only read when the counter changes.
@MainActor
final class ClipboardHistoryController {
    private static let enabledKey = "clipboardHistoryEnabled"
    private static let pollIntervalNanoseconds: UInt64 = 500_000_000

    private(set) var history = ClipboardHistory()
    var copyPolicy = CopyPolicy()

    private let pasteboard = NSPasteboard.general
    private let writer = PasteboardWriter()
    private var lastChangeCount: Int
    private var pollTask: Task<Void, Never>?

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        lastChangeCount = pasteboard.changeCount
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue {
                start()
            } else {
                stop()
                history.clear()
            }
        }
    }

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

    func clear() {
        history.clear()
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

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let types = (pasteboard.types ?? []).map(\.rawValue)
        // Check the markers before reading the contents, so concealed items are never read.
        guard !types.contains(where: ClipboardRecordPolicy.privateTypes.contains) else { return }
        let text = pasteboard.string(forType: .string)
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard ClipboardRecordPolicy.shouldRecord(
            text: text, pasteboardTypes: types, sourceBundleID: source, copyPolicy: copyPolicy
        ), let text else { return }
        history.record(text)
    }
}
