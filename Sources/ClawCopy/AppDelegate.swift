import AppKit
import ClawCopyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = CopyOnSelectController()
    private let mouseMonitor = MouseMonitor()
    private let keyboardMonitor = KeyboardMonitor()
    private let historyController = ClipboardHistoryController()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var permissionsMenuItem: NSMenuItem?
    private var openAtLoginMenuItem: NSMenuItem?
    private let historyMenu = NSMenu()
    private let modeMenu = NSMenu()
    private let historyViewer = HistoryTextViewer()
    private let historyPreview = HistoryPreviewPanel()
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.applyDefaultOnFirstLaunch()
        setUpMainMenu()
        setUpStatusItem()
        historyController.shouldPause = { [weak self] in
            self?.controller.isConvertingClipboard ?? false
        }
        historyController.start()

        mouseMonitor.onSelectionGesture = { [weak self] in
            self?.controller.selectionGestureEnded()
        }
        mouseMonitor.start()

        keyboardMonitor.onSelectionGesture = { [weak self] in
            self?.controller.selectionGestureEnded()
        }
        // Started from refreshStatus() once Accessibility access is granted: macOS only
        // delivers key events to global monitors of trusted apps.

        if !Permissions.isTrusted(prompt: true) {
            waitForPermission()
        }
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
        keyboardMonitor.stop()
        historyController.stop()
        permissionTask?.cancel()
    }

    // MARK: - Menu bar

    /// Menu bar apps have no visible main menu, but it is what routes ⌘C / ⌘A / ⌘W to the
    /// history viewer window.
    private func setUpMainMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let permissions = NSMenuItem(
            title: "Grant Accessibility Permission…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(.separator())
        for mode in CopyMode.allCases {
            let modeItem = NSMenuItem(title: mode.title, action: #selector(selectCopyMode(_:)), keyEquivalent: "")
            modeItem.target = self
            modeItem.representedObject = mode.rawValue
            modeMenu.addItem(modeItem)
        }
        let copyMode = NSMenuItem(title: "Copy Mode", action: nil, keyEquivalent: "")
        copyMode.submenu = modeMenu
        menu.addItem(copyMode)

        let history = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        history.submenu = historyMenu
        historyMenu.delegate = self
        menu.addItem(history)

        menu.addItem(.separator())
        let openAtLogin = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        openAtLogin.target = self
        menu.addItem(openAtLogin)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Claw Copy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusMenuItem = status
        permissionsMenuItem = permissions
        openAtLoginMenuItem = openAtLogin
        refreshOpenAtLogin()
        refreshCopyMode()
    }

    // MARK: - Copy mode

    @objc private func selectCopyMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CopyMode(rawValue: raw) else { return }
        controller.mode = mode
        refreshCopyMode()
    }

    /// Checkmarks the active mode and shows it in the menu bar icon (# for Markdown).
    private func refreshCopyMode() {
        let mode = controller.mode
        for item in modeMenu.items {
            item.state = (item.representedObject as? String) == mode.rawValue ? .on : .off
        }
        let symbol = mode == .markdown ? "number.square" : "doc.on.clipboard"
        let description = "Claw Copy (\(mode.title))"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: description)
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = description
        refreshStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu !== historyMenu else { return }
        // The user may have changed it in System Settings › Login Items meanwhile.
        refreshOpenAtLogin()
        rebuildHistoryMenu()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard menu === historyMenu else { return }
        let entries = historyController.history.entries
        if let item, !item.isAlternate, let index = item.representedObject as? Int, entries.indices.contains(index) {
            historyPreview.show(HistoryPreview.make(entries[index]))
        } else {
            historyPreview.hide()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        historyPreview.hide()
    }

    // MARK: - Clipboard history

    private func rebuildHistoryMenu() {
        historyMenu.removeAllItems()
        let entries = historyController.history.entries

        if !historyController.isEnabled {
            historyMenu.addItem(disabledItem("History is off"))
        } else if entries.isEmpty {
            historyMenu.addItem(disabledItem("Nothing copied yet"))
        } else {
            for (index, text) in entries.enumerated() {
                let title = HistoryMenuTitle.make(text)
                let key = index < 9 ? String(index + 1) : ""

                let item = NSMenuItem(title: title, action: #selector(restoreHistoryItem(_:)), keyEquivalent: key)
                item.keyEquivalentModifierMask = []
                item.target = self
                item.tag = index
                // Hover preview (shown beside the menu), built only when the entry is highlighted.
                item.representedObject = index
                historyMenu.addItem(item)

                // Shown instead of the item above while ⌥ Option is held.
                let showFull = NSMenuItem(
                    title: "Show Full Text… \(HistoryMenuTitle.make(text, maxLength: 44))",
                    action: #selector(showHistoryItem(_:)),
                    keyEquivalent: key
                )
                showFull.keyEquivalentModifierMask = [.option]
                showFull.isAlternate = true
                showFull.target = self
                showFull.tag = index
                historyMenu.addItem(showFull)
            }
            historyMenu.addItem(hintItem("Hold ⌥ Option to show full text"))
        }

        historyMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !entries.isEmpty
        historyMenu.addItem(clear)

        let keep = NSMenuItem(title: "Keep Clipboard History", action: #selector(toggleHistory), keyEquivalent: "")
        keep.target = self
        keep.state = historyController.isEnabled ? .on : .off
        historyMenu.addItem(keep)
    }

    /// A small, greyed-out explanatory line, like the hints in macOS's own menus.
    private func hintItem(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func restoreHistoryItem(_ sender: NSMenuItem) {
        historyController.restore(at: sender.tag)
    }

    @objc private func showHistoryItem(_ sender: NSMenuItem) {
        let entries = historyController.history.entries
        guard entries.indices.contains(sender.tag) else { return }
        historyViewer.show(entries[sender.tag]) { [weak self] text in
            self?.historyController.copyToClipboard(text)
        }
    }

    @objc private func clearHistory() {
        historyController.clear()
    }

    @objc private func toggleHistory() {
        historyController.isEnabled.toggle()
    }

    private func refreshOpenAtLogin() {
        let state = LoginItem.state
        openAtLoginMenuItem?.state = LaunchAtLoginPolicy.isOn(state) ? .on : .off
        openAtLoginMenuItem?.isEnabled = state != .unavailable
    }

    // MARK: - Open at Login

    @objc private func toggleOpenAtLogin() {
        let enable = !LaunchAtLoginPolicy.isOn(LoginItem.state)
        do {
            try LoginItem.setEnabled(enable)
        } catch {
            let alert = NSAlert()
            alert.messageText = enable ? "Couldn't turn on Open at Login" : "Couldn't turn off Open at Login"
            alert.informativeText = "You can change it in System Settings › General › Login Items."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                LoginItem.openLoginItemsSettings()
            }
        }
        if LoginItem.state == .requiresApproval {
            LoginItem.openLoginItemsSettings()
        }
        refreshOpenAtLogin()
    }

    private func refreshStatus() {
        let trusted = Permissions.isTrusted(prompt: false)
        statusMenuItem?.title = trusted
            ? "Copy on select is active · \(controller.mode.title)"
            : "Waiting for Accessibility permission"
        permissionsMenuItem?.isHidden = trusted
        if trusted {
            keyboardMonitor.start()
        }
    }

    // MARK: - Permissions

    private func waitForPermission() {
        permissionTask?.cancel()
        permissionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if Permissions.isTrusted(prompt: false) {
                    self?.refreshStatus()
                    return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
        waitForPermission()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
