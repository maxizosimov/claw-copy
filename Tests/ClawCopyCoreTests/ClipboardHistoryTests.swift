import XCTest
@testable import ClawCopyCore

final class ClipboardHistoryTests: XCTestCase {
    func testNewestFirst() {
        var history = ClipboardHistory()
        history.record("one")
        history.record("two")
        XCTAssertEqual(history.entries, ["two", "one"])
    }

    func testDuplicateMovesToTop() {
        var history = ClipboardHistory()
        history.record("one")
        history.record("two")
        XCTAssertTrue(history.record("one"))
        XCTAssertEqual(history.entries, ["one", "two"])
        XCTAssertFalse(history.record("one"), "re-recording the newest entry is a no-op")
    }

    func testCapacityDropsOldest() {
        var history = ClipboardHistory(capacity: 3)
        for text in ["a", "b", "c", "d"] { history.record(text) }
        XCTAssertEqual(history.entries, ["d", "c", "b"])
    }

    func testClear() {
        var history = ClipboardHistory()
        history.record("secret-ish")
        history.clear()
        XCTAssertTrue(history.entries.isEmpty)
    }
}

final class ClipboardRecordPolicyTests: XCTestCase {
    func testRecordsOrdinaryText() {
        XCTAssertTrue(ClipboardRecordPolicy.shouldRecord(
            text: "hello", pasteboardTypes: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari"))
    }

    func testNeverRecordsConcealedOrTransientContent() {
        for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"] {
            XCTAssertFalse(ClipboardRecordPolicy.shouldRecord(
                text: "hunter2", pasteboardTypes: ["public.utf8-plain-text", type], sourceBundleID: nil), type)
        }
    }

    func testNeverRecordsFromPasswordManagers() {
        XCTAssertFalse(ClipboardRecordPolicy.shouldRecord(
            text: "hunter2", pasteboardTypes: ["public.utf8-plain-text"], sourceBundleID: "com.bitwarden.desktop"))
    }

    func testSkipsEmptyWhitespaceAndOversized() {
        XCTAssertFalse(ClipboardRecordPolicy.shouldRecord(text: nil, pasteboardTypes: [], sourceBundleID: nil))
        XCTAssertFalse(ClipboardRecordPolicy.shouldRecord(text: " \n\t", pasteboardTypes: [], sourceBundleID: nil))
        let small = CopyPolicy(maxLength: 3)
        XCTAssertFalse(ClipboardRecordPolicy.shouldRecord(
            text: "1234", pasteboardTypes: [], sourceBundleID: nil, copyPolicy: small))
    }
}

final class HistoryMenuTitleTests: XCTestCase {
    func testCollapsesWhitespaceToOneLine() {
        XCTAssertEqual(HistoryMenuTitle.make("  first line\n\n\tsecond   line \r\n"), "first line second line")
    }

    func testTruncatesLongText() {
        let title = HistoryMenuTitle.make(String(repeating: "x", count: 100), maxLength: 10)
        XCTAssertEqual(title, String(repeating: "x", count: 9) + "…")
        XCTAssertEqual(title.count, 10)
    }

    func testStripsBidiOverridesAndZeroWidthCharacters() {
        // U+202E would render "exe.txt" reversed, disguising what the entry really is.
        XCTAssertEqual(HistoryMenuTitle.make("invoice\u{202E}txt.exe"), "invoicetxt.exe")
        XCTAssertEqual(HistoryMenuTitle.make("pa\u{200B}ss\u{FEFF}word"), "password")
    }

    func testInvisibleOnlyTextGetsAPlaceholder() {
        XCTAssertEqual(HistoryMenuTitle.make("\u{200B}\u{202E}"), HistoryMenuTitle.invisiblePlaceholder)
    }

    func testKeepsEmojiAndNonLatinTextIntact() {
        XCTAssertEqual(HistoryMenuTitle.make("Привет 👋🏽 世界"), "Привет 👋🏽 世界")
        XCTAssertEqual(HistoryMenuTitle.make("👋🏽👋🏽👋🏽", maxLength: 2), "👋🏽…")
    }
}

final class HistoryPreviewTests: XCTestCase {
    func testShortTextIsShownInFullWithLineBreaks() {
        XCTAssertEqual(HistoryPreview.make("line 1\r\nline 2\rline 3\n\tindented"), "line 1\nline 2\nline 3\n    indented")
    }

    func testLongTextIsCutByLines() {
        let text = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let preview = HistoryPreview.make(text, maxLines: 3)
        XCTAssertTrue(preview.hasPrefix("line 1\nline 2\nline 3\n…"))
        XCTAssertFalse(preview.contains("line 4"))
        XCTAssertTrue(preview.contains("Show Full Text"))
    }

    func testLongTextIsCutByCharacters() {
        let preview = HistoryPreview.make(String(repeating: "x", count: 5000), maxCharacters: 100)
        XCTAssertTrue(preview.hasPrefix(String(repeating: "x", count: 100) + "\n…"))
        XCTAssertFalse(preview.hasPrefix(String(repeating: "x", count: 101)))
    }

    func testStripsInvisibleAndControlCharacters() {
        XCTAssertEqual(HistoryPreview.make("a\u{202E}b\u{0007}c\u{200B}"), "abc")
        XCTAssertEqual(HistoryPreview.make("\u{200B}\u{FEFF}"), HistoryMenuTitle.invisiblePlaceholder)
    }
}
