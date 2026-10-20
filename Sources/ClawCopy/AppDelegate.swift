import AppKit
import ClawCopyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = CopyOnSelectController()
    private let mouseMonitor = MouseMonitor()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var permissionsMenuItem: NSMenuItem?
    private var permissionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        mouseMonitor.onSelectionGesture = { [weak self] in
            self?.controller.selectionGestureEnded()
        }
        mouseMonitor.start()

        if !Permissions.isTrusted(prompt: true) {
            waitForPermission()
        }
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mouseMonitor.stop()
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
        let quit = NSMenuItem(title: "Quit Claw Copy", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        statusMenuItem = status
        permissionsMenuItem = permissions
    }

    private func refreshStatus() {
        let trusted = Permissions.isTrusted(prompt: false)
        statusMenuItem?.title = trusted
            ? "Copy on select is active"
            : "Waiting for Accessibility permission"
        permissionsMenuItem?.isHidden = trusted
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
