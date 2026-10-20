import AppKit
import ApplicationServices

/// What the Accessibility API reports about the focused element of the frontmost app.
struct SelectionSnapshot {
    var selectedText: String?
    var role: String?
    var isSecureField: Bool
    var bundleID: String?
}

/// Reads the current text selection of the focused UI element via the Accessibility API.
/// Read-only: it never changes anything in the other app.
@MainActor
final class SelectionReader {
    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        // Never let an unresponsive app stall Claw Copy.
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    func read() -> SelectionSnapshot {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let element = focusedElement() else {
            return SelectionSnapshot(selectedText: nil, role: nil, isSecureField: false, bundleID: frontmostBundleID)
        }

        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        let isSecure = subrole == (kAXSecureTextFieldSubrole as String)

        var pid: pid_t = 0
        var bundleID = frontmostBundleID
        if AXUIElementGetPid(element, &pid) == .success,
           let app = NSRunningApplication(processIdentifier: pid) {
            bundleID = app.bundleIdentifier ?? bundleID
        }

        // Do not even read the contents of secure fields.
        let text = isSecure ? nil : stringAttribute(kAXSelectedTextAttribute, of: element)
        return SelectionSnapshot(selectedText: text, role: role, isSecureField: isSecure, bundleID: bundleID)
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
