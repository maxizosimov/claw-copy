import ClawCopyCore
import Foundation
import ServiceManagement

/// "Open at Login" via SMAppService.mainApp: macOS's standard login item for this app itself.
/// It installs no helper, daemon or launch agent. The user can see and remove it in
/// System Settings › General › Login Items.
@MainActor
enum LoginItem {
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    /// Turns "Open at Login" on the first time the app launches (on by default).
    static func applyDefaultOnFirstLaunch() {
        let defaults = UserDefaults.standard
        let applied = defaults.bool(forKey: defaultAppliedKey)
        if LaunchAtLoginPolicy.shouldEnableOnLaunch(defaultApplied: applied, state: state) {
            try? SMAppService.mainApp.register()
        }
        defaults.set(true, forKey: defaultAppliedKey)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
