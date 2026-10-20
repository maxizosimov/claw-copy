import AppKit
import ClawCopyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = CopyOnSelectController()
    private let mouseMonitor = MouseMonitor()
    private let keyboardMonitor = KeyboardMonitor()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var permissionsMenuItem: NSMenuItem?
    private var openAtLoginMenuItem: NSMenuItem?
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.applyDefaultOnFirstLaunch()
        setUpStatusItem()

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
        permissionTask?.cancel()
    }

    // MARK: - Menu bar

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
