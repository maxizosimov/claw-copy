import Foundation

public enum SkipReason: Equatable, Sendable {
    /// The source application is on the exclusion list (e.g. a password manager).
    case excludedApp
    /// The selection came from a password / secure text field.
    case secureField
    /// Nothing (or only whitespace) is selected.
    case empty
    /// The selection exceeds the configured size limit.
    case tooLong
    /// The selection is already exactly what is on the clipboard.
    case duplicate
}

public enum CopyDecision: Equatable, Sendable {
    case copy(String)
    case skip(SkipReason)
}

/// Decides whether a selection read from another app should be put on the clipboard.
///
/// The selected text is treated strictly as inert data: it is never parsed as a command,
/// executed, opened, or sent anywhere. The policy only decides *whether* to copy it.
public struct CopyPolicy: Sendable {
    /// Apps whose selections are never copied. Matched case-insensitively.
    public var excludedBundleIDs: Set<String>
    /// Maximum selection length in UTF-16 code units (what NSPasteboard stores).
    public var maxLength: Int

    public static let defaultMaxLength = 1_000_000

    /// Password managers and other apps that routinely display secrets.
    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop",
    ]

    public init(
        excludedBundleIDs: Set<String> = CopyPolicy.defaultExcludedBundleIDs,
        maxLength: Int = CopyPolicy.defaultMaxLength
    ) {
        self.excludedBundleIDs = Set(excludedBundleIDs.map { $0.lowercased() })
        self.maxLength = maxLength
    }

    public func isExcluded(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID.lowercased())
    }

    public func evaluate(
        text: String?,
        sourceBundleID: String?,
        isSecureField: Bool,
        currentClipboard: String?
    ) -> CopyDecision {
        if isExcluded(bundleID: sourceBundleID) { return .skip(.excludedApp) }
        if isSecureField { return .skip(.secureField) }
        guard let text, !text.allSatisfy(\.isWhitespace) else { return .skip(.empty) }
        if text.utf16.count > maxLength { return .skip(.tooLong) }
        if text == currentClipboard { return .skip(.duplicate) }
        // Copy the selection exactly as selected; no trimming or rewriting.
        return .copy(text)
    }
}
