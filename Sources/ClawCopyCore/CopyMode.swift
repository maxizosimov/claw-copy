import Foundation

/// What copy-on-select puts on the clipboard.
public enum CopyMode: String, CaseIterable, Sendable {
    /// The selected text, as plain text.
    case plainText
    /// Formatted selections (web pages, chat replies, docs) converted to Markdown.
    case markdown

    public var title: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        }
    }
}

/// What to do with a selection, given the copy policy's decision and the copy mode.
public enum CaptureAction: Equatable, Sendable {
    case none
    /// Put this exact text on the clipboard.
    case writePlain(String)
    /// Send the app a normal Cmd+C (and, in Markdown mode, convert what it copies).
    case sendCopyKeystroke
}

public enum CapturePlanner {
    public static func plan(decision: CopyDecision, mode: CopyMode, fallbackAllowed: Bool) -> CaptureAction {
        switch (mode, decision) {
        case (_, .skip(.excludedApp)), (_, .skip(.secureField)), (_, .skip(.tooLong)):
            return .none

        case (.plainText, .copy(let text)):
            return .writePlain(text)
        case (.plainText, .skip(.empty)):
            // The app may not expose its selection via Accessibility (e.g. browsers).
            return fallbackAllowed ? .sendCopyKeystroke : .none
        case (.plainText, .skip(.duplicate)):
            return .none

        // Markdown needs the app's formatted copy (HTML), which only Cmd+C provides.
        case (.markdown, .copy(let text)):
            return fallbackAllowed ? .sendCopyKeystroke : .writePlain(text)
        case (.markdown, .skip(.empty)), (.markdown, .skip(.duplicate)):
            return fallbackAllowed ? .sendCopyKeystroke : .none
        }
    }
}
