import Foundation

/// Some apps (Chromium/Electron web content, many custom editors) do not expose the selected
/// text through the Accessibility API. For those, Claw Copy can fall back to sending the app a
/// standard Cmd+C. This policy limits that fallback to contexts where it is safe and expected,
/// so double-clicking a file in Finder or dragging a slider never touches the clipboard.
public struct KeystrokeFallbackPolicy: Sendable {
    public var isEnabled: Bool
    /// Apps where Cmd+C after a click means "copy files/objects", not "copy text".
    public var excludedBundleIDs: Set<String>

    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systempreferences",
        "com.apple.Photos",
        "com.apple.ActivityMonitor",
    ]

    /// Accessibility roles for focused elements that are not text, where Cmd+C would copy
    /// something other than a text selection (files, rows, images) or nothing useful.
    public static let nonTextRoles: Set<String> = [
        "AXBrowser", "AXButton", "AXCheckBox", "AXDockItem", "AXGrowArea", "AXImage",
        "AXList", "AXMenu", "AXMenuBar", "AXMenuBarItem", "AXMenuButton", "AXMenuItem",
        "AXOutline", "AXPopUpButton", "AXRadioButton", "AXScrollBar", "AXSlider",
        "AXSplitter", "AXTabGroup", "AXTable", "AXToolbar", "AXDisclosureTriangle",
    ]

    public init(
        isEnabled: Bool = true,
        excludedBundleIDs: Set<String> = KeystrokeFallbackPolicy.defaultExcludedBundleIDs
    ) {
        self.isEnabled = isEnabled
        self.excludedBundleIDs = Set(excludedBundleIDs.map { $0.lowercased() })
    }

    public func allowsFallback(focusedRole: String?, sourceBundleID: String?) -> Bool {
        guard isEnabled else { return false }
        if let sourceBundleID, excludedBundleIDs.contains(sourceBundleID.lowercased()) {
            return false
        }
        if let focusedRole, Self.nonTextRoles.contains(focusedRole) { return false }
        return true
    }
}
