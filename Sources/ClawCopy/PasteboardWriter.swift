import AppKit
import ClawCopyCore

/// Reads and writes the general pasteboard.
@MainActor
final class PasteboardWriter {
    /// Marks clipboard entries as coming from Claw Copy (nspasteboard.org convention).
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    /// The de-facto Markdown pasteboard type, alongside plain text.
    private static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    /// Tells clipboard managers (including Claw Copy's normal history) that this is a secret.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    var types: [String] { (pasteboard.types ?? []).map(\.rawValue) }

    /// The clipboard's text, unless an app marked it concealed or transient (password managers):
    /// that is never read.
    func currentString() -> String? {
        guard !types.contains(where: ClipboardRecordPolicy.privateTypes.contains) else { return nil }
        return pasteboard.string(forType: .string)
    }

    func currentHTML() -> String? {
        pasteboard.string(forType: .html)
    }

    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markAsOurs()
    }

    /// Replaces the clipboard with Markdown as plain text, so it pastes as Markdown everywhere.
    func writeMarkdown(_ markdown: String) {
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
        pasteboard.setString(markdown, forType: Self.markdownType)
        markAsOurs()
    }

    /// Writes a password, marked concealed so clipboard managers don't keep it.
    func writeConcealed(_ secret: String) {
        pasteboard.clearContents()
        pasteboard.setString(secret, forType: .string)
        pasteboard.setString("", forType: Self.concealedType)
        markAsOurs()
    }

    private func markAsOurs() {
        if let bundleID = Bundle.main.bundleIdentifier {
            pasteboard.setString(bundleID, forType: Self.sourceType)
        }
    }
}
