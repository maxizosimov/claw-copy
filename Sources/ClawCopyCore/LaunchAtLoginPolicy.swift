import Foundation

/// Whether Claw Copy is registered to open at login, as reported by macOS.
public enum LoginItemState: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user must approve it in System Settings › Login Items.
    case requiresApproval
    /// macOS can't register this copy of the app (e.g. not running from an app bundle).
    case unavailable
}

/// "Open at Login" is on by default: it is turned on once, on the first launch. After that the
/// user's choice is respected, so turning it off is never undone by a later launch.
public enum LaunchAtLoginPolicy {
    public static func shouldEnableOnLaunch(defaultApplied: Bool, state: LoginItemState) -> Bool {
        !defaultApplied && state == .disabled
    }

    /// The menu shows a checkmark when the app is registered, even if approval is pending.
    public static func isOn(_ state: LoginItemState) -> Bool {
        state == .enabled || state == .requiresApproval
    }
}
