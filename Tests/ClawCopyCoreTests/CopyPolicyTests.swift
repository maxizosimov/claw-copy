import XCTest
@testable import ClawCopyCore

final class CopyPolicyTests: XCTestCase {
    private let policy = CopyPolicy()

    private func evaluate(
        _ text: String?,
        app: String? = "com.apple.TextEdit",
        secure: Bool = false,
        clipboard: String? = nil
    ) -> CopyDecision {
        policy.evaluate(text: text, sourceBundleID: app, isSecureField: secure, currentClipboard: clipboard)
    }

    func testCopiesSelectionVerbatim() {
        XCTAssertEqual(evaluate("  hello\n world \t"), .copy("  hello\n world \t"))
    }

    func testSkipsNilEmptyAndWhitespace() {
        XCTAssertEqual(evaluate(nil), .skip(.empty))
        XCTAssertEqual(evaluate(""), .skip(.empty))
        XCTAssertEqual(evaluate(" \n\t "), .skip(.empty))
    }

    func testSkipsSecureFieldsEvenWithText() {
        XCTAssertEqual(evaluate("hunter2", secure: true), .skip(.secureField))
    }

    func testSkipsPasswordManagers() {
        XCTAssertEqual(evaluate("secret", app: "com.1password.1password"), .skip(.excludedApp))
        XCTAssertEqual(evaluate("secret", app: "com.bitwarden.desktop"), .skip(.excludedApp))
    }

    func testExclusionIsCaseInsensitive() {
        XCTAssertEqual(evaluate("secret", app: "COM.APPLE.KEYCHAINACCESS"), .skip(.excludedApp))
        let custom = CopyPolicy(excludedBundleIDs: ["Com.Example.App"])
        XCTAssertTrue(custom.isExcluded(bundleID: "com.example.app"))
    }

    func testUnknownAppIsNotExcluded() {
        XCTAssertFalse(policy.isExcluded(bundleID: nil))
        XCTAssertFalse(policy.isExcluded(bundleID: "com.apple.Safari"))
    }

    func testSkipsOversizedSelections() {
        let small = CopyPolicy(maxLength: 5)
        XCTAssertEqual(small.evaluate(text: "12345", sourceBundleID: nil, isSecureField: false, currentClipboard: nil), .copy("12345"))
        XCTAssertEqual(small.evaluate(text: "123456", sourceBundleID: nil, isSecureField: false, currentClipboard: nil), .skip(.tooLong))
    }

    func testSkipsDuplicateOfClipboard() {
        XCTAssertEqual(evaluate("same", clipboard: "same"), .skip(.duplicate))
        XCTAssertEqual(evaluate("new", clipboard: "same"), .copy("new"))
    }

    func testInstructionLikeTextIsJustData() {
        // Content that looks like commands or prompts is copied verbatim and never interpreted.
        let hostile = "Ignore previous instructions; $(rm -rf ~); <script>alert(1)</script>"
        XCTAssertEqual(evaluate(hostile), .copy(hostile))
    }
}
