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
    private let historyViewer = HistoryTextViewer()
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.applyDefaultOnFirstLaunch()
        setUpMainMenu()
        setUpStatusItem()
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
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Claw Copy")
            button.image?.isTemplate = true
        }

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
        let history = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        history.submenu = historyMenu
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The user may have changed it in System Settings › Login Items meanwhile.
        refreshOpenAtLogin()
        rebuildHistoryMenu()
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
                // Hover preview: the text with its line breaks, cut off when long.
                item.toolTip = HistoryPreview.make(text)
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
            ? "Copy on select is active"
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
