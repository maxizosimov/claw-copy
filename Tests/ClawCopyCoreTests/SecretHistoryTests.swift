import XCTest
@testable import ClawCopyCore

final class SecretHistoryTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testEntriesExpireAfterTheirLifetime() {
        var secrets = SecretHistory(lifetime: 60)
        secrets.record("hunter2", sourceName: "1Password", at: t0)
        secrets.purgeExpired(at: t0.addingTimeInterval(59))
        XCTAssertEqual(secrets.entries.map(\.text), ["hunter2"])
        secrets.purgeExpired(at: t0.addingTimeInterval(60))
        XCTAssertTrue(secrets.entries.isEmpty)
    }

    func testRestoringDoesNotExtendLifetime() {
        var secrets = SecretHistory(lifetime: 60)
        secrets.record("a", sourceName: "1Password", at: t0)
        secrets.record("b", sourceName: "1Password", at: t0.addingTimeInterval(10))
        // Copying "a" again (e.g. restoring it) moves it to the top but keeps its copy time.
        secrets.record("a", sourceName: nil, at: t0.addingTimeInterval(50))
        XCTAssertEqual(secrets.entries.map(\.text), ["a", "b"])
        XCTAssertEqual(secrets.entries.first?.copiedAt, t0)
        XCTAssertEqual(secrets.entries.first?.sourceName, "1Password")
        secrets.purgeExpired(at: t0.addingTimeInterval(65))
        XCTAssertEqual(secrets.entries.map(\.text), ["b"])
    }

    func testCapacity() {
        var secrets = SecretHistory(lifetime: 600, capacity: 2)
        for (i, text) in ["a", "b", "c"].enumerated() {
            secrets.record(text, sourceName: nil, at: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(secrets.entries.map(\.text), ["c", "b"])
    }

    func testMenuTitleIsMaskedAndShowsTimeLeft() {
        var secrets = SecretHistory(lifetime: 300)
        secrets.record("correct horse battery staple", sourceName: "1Password", at: t0)
        let entry = secrets.entries[0]
        let title = secrets.menuTitle(for: entry, at: t0.addingTimeInterval(30))
        XCTAssertEqual(title, "•••••••• · 1Password · 5 min left")
        XCTAssertFalse(title.contains("horse"))
        XCTAssertEqual(secrets.menuTitle(for: entry, at: t0.addingTimeInterval(290)), "•••••••• · 1Password · 10 s left")
    }

    func testMaskDoesNotRevealLength() {
        var secrets = SecretHistory(lifetime: 60)
        secrets.record("a", sourceName: nil, at: t0)
        secrets.record(String(repeating: "x", count: 64), sourceName: nil, at: t0)
        let titles = secrets.entries.map { secrets.menuTitle(for: $0, at: t0) }
        XCTAssertEqual(titles[0], titles[1])
    }

    func testClear() {
        var secrets = SecretHistory(lifetime: 60)
        secrets.record("x", sourceName: nil, at: t0)
        secrets.clear()
        XCTAssertTrue(secrets.entries.isEmpty)
    }
}

final class ClipboardKindTests: XCTestCase {
    func testConcealedCopiesAreSecrets() {
        XCTAssertEqual(ClipboardRecordPolicy.kind(
            pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], sourceBundleID: "com.apple.Safari"), .secret)
        XCTAssertEqual(ClipboardRecordPolicy.kind(
            pasteboardTypes: ["public.utf8-plain-text", "com.agilebits.onepassword"], sourceBundleID: nil), .secret)
    }

    func testCopiesInPasswordManagersAreSecrets() {
        XCTAssertEqual(ClipboardRecordPolicy.kind(
            pasteboardTypes: ["public.utf8-plain-text"], sourceBundleID: "com.bitwarden.desktop"), .secret)
    }

    func testTransientCopiesAreNeverKept() {
        XCTAssertEqual(ClipboardRecordPolicy.kind(
            pasteboardTypes: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"], sourceBundleID: nil), .ignore)
    }

    func testOrdinaryCopies() {
        XCTAssertEqual(ClipboardRecordPolicy.kind(
            pasteboardTypes: ["public.utf8-plain-text"], sourceBundleID: "com.apple.TextEdit"), .ordinary)
    }
}
