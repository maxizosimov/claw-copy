import AppKit

/// A small read-only window that shows one clipboard history entry in full.
///
/// The text is shown as plain text: it is never interpreted as rich text, HTML or links.
@MainActor
final class HistoryTextViewer: NSObject {
    private var window: NSWindow?
    private let textView: NSTextView
    private let scrollView: NSScrollView
    private let infoLabel = NSTextField(labelWithString: "")
    private var text = ""
    private var onCopy: ((String) -> Void)?

    override init() {
        let scroll = NSTextView.scrollableTextView()
        scrollView = scroll
        textView = scroll.documentView as! NSTextView
        super.init()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
    }

    func show(_ text: String, onCopy: @escaping (String) -> Void) {
        self.text = text
        self.onCopy = onCopy
        let window = self.window ?? makeWindow()
        self.window = window

        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        infoLabel.stringValue = "\(text.count.formatted(.number)) characters, \(lines.formatted(.number)) lines"

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let size = NSSize(width: 560, height: 420)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipboard History"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 200)

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        scrollView.frame = NSRect(x: 0, y: 44, width: size.width, height: size.height - 44)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        content.addSubview(scrollView)

        infoLabel.frame = NSRect(x: 12, y: 14, width: 300, height: 18)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(infoLabel)

        let copyButton = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copyText))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"
        copyButton.sizeToFit()
        copyButton.frame.origin = NSPoint(x: size.width - copyButton.frame.width - 12, y: 8)
        copyButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(copyButton)

        window.contentView = content
        window.center()
        return window
    }

    @objc private func copyText() {
        onCopy?(text)
        window?.close()
    }
}
