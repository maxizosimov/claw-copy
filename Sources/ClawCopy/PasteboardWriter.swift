import AppKit

/// Writes plain text to the general pasteboard.
@MainActor
final class PasteboardWriter {
    /// Marks clipboard entries as coming from Claw Copy (nspasteboard.org convention).
    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    private let pasteboard = NSPasteboard.general

    func currentString() -> String? {
        pasteboard.string(forType: .string)
    }

    func write(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if let bundleID = Bundle.main.bundleIdentifier {
            pasteboard.setString(bundleID, forType: Self.sourceType)
        }
    }
}
