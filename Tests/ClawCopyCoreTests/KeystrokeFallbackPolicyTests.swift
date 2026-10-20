import XCTest
@testable import ClawCopyCore

final class KeystrokeFallbackPolicyTests: XCTestCase {
    func testAllowsTextContexts() {
        let policy = KeystrokeFallbackPolicy()
        XCTAssertTrue(policy.allowsFallback(focusedRole: "AXWebArea", sourceBundleID: "com.google.Chrome"))
        XCTAssertTrue(policy.allowsFallback(focusedRole: "AXTextArea", sourceBundleID: "com.microsoft.VSCode"))
        XCTAssertTrue(policy.allowsFallback(focusedRole: nil, sourceBundleID: "com.tinyspeck.slackmacgap"))
    }

    func testNeverInFinderOrDock() {
        let policy = KeystrokeFallbackPolicy()
        XCTAssertFalse(policy.allowsFallback(focusedRole: nil, sourceBundleID: "com.apple.finder"))
        XCTAssertFalse(policy.allowsFallback(focusedRole: "AXTextArea", sourceBundleID: "com.apple.Finder"))
        XCTAssertFalse(policy.allowsFallback(focusedRole: nil, sourceBundleID: "com.apple.dock"))
    }

    func testNeverOnNonTextElements() {
        let policy = KeystrokeFallbackPolicy()
        for role in ["AXList", "AXOutline", "AXTable", "AXButton", "AXImage", "AXSlider"] {
            XCTAssertFalse(policy.allowsFallback(focusedRole: role, sourceBundleID: "com.example.app"), role)
        }
    }

    func testDisabled() {
        let policy = KeystrokeFallbackPolicy(isEnabled: false)
        XCTAssertFalse(policy.allowsFallback(focusedRole: "AXWebArea", sourceBundleID: "com.google.Chrome"))
    }
}
