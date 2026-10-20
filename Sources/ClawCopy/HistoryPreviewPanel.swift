import AppKit

/// A preview of a clipboard history entry shown beside the history menu while an entry is
/// highlighted, positioned like a submenu. It never takes focus or mouse clicks.
@MainActor
final class HistoryPreviewPanel {
    private static let showDelayNanoseconds: UInt64 = 350_000_000
    private static let maxTextWidth: CGFloat = 380
    private static let padding: CGFloat = 10
    private static let gap: CGFloat = 4

    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "⌥ Option-click to show the full text")
    private static let footerGap: CGFloat = 6
    private var pending: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        panel.contentView = background

        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = Self.maxTextWidth
        label.isSelectable = false
        background.addSubview(label)

        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor
        background.addSubview(footer)
    }

    /// Shows `text` (already a sanitized preview) after a short hover delay.
    func show(_ text: String) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.showDelayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.present(text)
        }
    }

    func hide() {
        pending?.cancel()
        pending = nil
        panel.orderOut(nil)
    }

    private func present(_ text: String) {
        label.stringValue = text
        let textSize = label.fittingSize
        let footerSize = footer.fittingSize
        let contentWidth = min(max(textSize.width, footerSize.width), Self.maxTextWidth)
        let width = contentWidth + Self.padding * 2
        let height = textSize.height + Self.footerGap + footerSize.height + Self.padding * 2
        footer.frame = NSRect(x: Self.padding, y: Self.padding, width: contentWidth, height: footerSize.height)
        label.frame = NSRect(
            x: Self.padding,
            y: Self.padding + footerSize.height + Self.footerGap,
            width: contentWidth,
            height: textSize.height
        )

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .infinite
        // The history menu's own window: the visible pop-up-menu-level window under the pointer.
        let menuFrame = NSApp.windows.first {
            $0 !== panel && $0.isVisible
                && $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue
                && $0.frame.contains(mouse)
        }?.frame ?? NSRect(origin: mouse, size: .zero)

        // Beside the menu like a submenu: right if it fits, otherwise left.
        var x = menuFrame.maxX + Self.gap
        if x + width > visible.maxX {
            x = menuFrame.minX - Self.gap - width
        }
        // Top-aligned with the highlighted entry, kept on screen.
        var y = mouse.y + 12 - height
        y = max(visible.minY, min(y, visible.maxY - height))
        x = max(visible.minX, min(x, visible.maxX - width))

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFront(nil)
    }
}
