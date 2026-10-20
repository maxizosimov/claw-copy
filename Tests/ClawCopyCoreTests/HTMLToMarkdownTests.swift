import XCTest
@testable import ClawCopyCore

final class HTMLToMarkdownTests: XCTestCase {
    private func md(_ html: String) -> String? { HTMLToMarkdown.convert(html) }

    // MARK: Structure

    func testHeadingsAndParagraphs() {
        XCTAssertEqual(md("<h1>Title</h1><p>Hello <b>world</b></p><h3>Sub</h3>"), "# Title\n\nHello **world**\n\n### Sub")
    }

    func testInlineFormatting() {
        XCTAssertEqual(md("<p><em>a</em> <code>x`y</code> <del>d</del> <strong><i>both</i></strong></p>"),
                       "*a* ``x`y`` ~~d~~ ***both***")
    }

    func testEmphasisKeepsSpacesOutsideMarkers() {
        XCTAssertEqual(md("<p>a<b> bold </b>b</p>"), "a **bold** b")
    }

    func testLineBreaks() {
        XCTAssertEqual(md("<p>a<br>b<br/>c</p>"), "a\nb\nc")
    }

    func testWhitespaceIsCollapsed() {
        XCTAssertEqual(md("<p>  a \n\t b  </p>\n\n  <p>c</p>"), "a b\n\nc")
    }

    func testNestedLists() {
        XCTAssertEqual(md("<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>"), "- a\n  - b\n- c")
    }

    func testListDirectlyInsideListBelongsToPreviousItem() {
        XCTAssertEqual(md("<ul><li>a</li><ul><li>b</li></ul></ul>"), "- a\n  - b")
    }

    func testOrderedListWithStart() {
        XCTAssertEqual(md("<ol start=\"3\"><li>x</li><li>y</li></ol>"), "3. x\n4. y")
    }

    func testImplicitlyClosedListItems() {
        XCTAssertEqual(md("<ul><li>one<li>two</ul>"), "- one\n- two")
    }

    func testTaskList() {
        XCTAssertEqual(md("<ul><li><input type=\"checkbox\" checked> done</li><li><input type=\"checkbox\"> todo</li></ul>"),
                       "- [x] done\n- [ ] todo")
    }

    func testBlockquote() {
        XCTAssertEqual(md("<blockquote><p>q1</p><p>q2</p></blockquote>"), "> q1\n>\n> q2")
    }

    func testCodeBlockWithLanguage() {
        XCTAssertEqual(md("<pre><code class=\"language-swift\">let a = 1\n  b &lt; c\n</code></pre>"),
                       "```swift\nlet a = 1\n  b < c\n```")
    }

    func testCodeBlockFenceIsLongerThanBackticksInside() {
        XCTAssertEqual(md("<pre>```\nx\n```</pre>"), "````\n```\nx\n```\n````")
    }

    func testTable() {
        XCTAssertEqual(md("<table><thead><tr><th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>x|y</td></tr><tr><td>2</td></tr></tbody></table>"),
                       "| A | B |\n| --- | --- |\n| 1 | x\\|y |\n| 2 |  |")
    }

    func testHorizontalRule() {
        XCTAssertEqual(md("<p>a</p><hr><p>b</p>"), "a\n\n---\n\nb")
    }

    // MARK: Links

    func testSafeLinks() {
        XCTAssertEqual(md("<a href=\"https://example.com/a b(c)\">site</a>"), "[site](https://example.com/a%20b%28c%29)")
        XCTAssertEqual(md("<a href=\"mailto:me@example.com\">mail</a>"), "[mail](mailto:me@example.com)")
        XCTAssertEqual(md("<a href=\"https://a.b\"><b>x</b></a>"), "[**x**](https://a.b)")
    }

    func testUnsafeLinksKeepOnlyTheirText() {
        XCTAssertEqual(md("<a href=\"javascript:alert(1)\">click</a>"), "click")
        XCTAssertEqual(md("<a href=\"JaVa&#x09;Script:alert(1)\">tab</a>"), "tab")
        XCTAssertEqual(md("<a href=\"data:text/html,<script>alert(1)</script>\">data</a>"), "data")
        XCTAssertEqual(md("<a href=\"file:///etc/passwd\">file</a>"), "file")
        XCTAssertEqual(md("<a href=\"/relative\">rel</a>"), "rel")
    }

    // MARK: Safety

    func testScriptsStylesCommentsAndHeadAreDropped() {
        XCTAssertEqual(md("<html><head><title>T</title><style>p{color:red}</style></head><body><!--StartFragment--><script>alert('x')</script><p>ok</p><!--EndFragment--></body></html>"), "ok")
    }

    func testEventHandlersAndImagesAreDropped() {
        XCTAssertEqual(md("<p onclick=\"steal()\">hi</p><img src=\"https://tracker.example/x.png\" onerror=\"alert(1)\">"), "hi")
    }

    func testImageAltTextIsKept() {
        XCTAssertEqual(md("<p><img src=\"x.png\" alt=\"logo\"> hi</p>"), "logo hi")
    }

    func testDeepNestingDoesNotCrash() {
        XCTAssertEqual(md(String(repeating: "<div><span>", count: 20_000) + "x"), "x")
    }

    func testUnterminatedTagsStayLinearTime() {
        // Each unclosed attribute quote used to make the tokenizer rescan to the end of input.
        let hostile = String(repeating: "<a x=\"", count: 150_000)
        let start = Date()
        XCTAssertNotNil(md(hostile))
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(md("<p>ok</p><a href=\"x"), "ok\n\n\\<a href=\"x")
    }

    func testOversizedInputIsNotConverted() {
        XCTAssertNil(md(String(repeating: "a", count: HTMLToMarkdown.maxInputBytes + 1)))
    }

    func testEmptyInput() {
        XCTAssertNil(md(""))
        XCTAssertNil(md("<p> </p><script>x</script>"))
    }

    func testMalformedHTML() {
        XCTAssertEqual(md("<p>unclosed <b>bold"), "unclosed **bold**")
        XCTAssertEqual(md("<div><p>x</div>y"), "x\n\ny")
        XCTAssertEqual(md("a < b and <3 and <b"), "a \\< b and \\<3 and \\<b")
        XCTAssertEqual(md("</p></b>text"), "text")
    }

    // MARK: Escaping

    func testMarkdownCharactersInTextAreEscaped() {
        XCTAssertEqual(md("<p>*not bold* [x] snake_case _x_ `tick` back\\slash</p>"),
                       "\\*not bold\\* \\[x\\] snake_case \\_x\\_ \\`tick\\` back\\\\slash")
    }

    func testLineStartsThatWouldBecomeMarkdownAreEscaped() {
        XCTAssertEqual(md("<p># not heading</p><p>1. not list</p><p>- not item</p><p>&gt; not quote</p>"),
                       "\\# not heading\n\n1\\. not list\n\n\\- not item\n\n\\> not quote")
    }

    func testEntities() {
        XCTAssertEqual(md("<p>a &amp; b &lt;c&gt; &#x1F600; &nbsp;d &mdash; &unknown; &#0;</p>"),
                       "a & b \\<c> 😀 d — &unknown; \u{FFFD}")
    }

    // MARK: Real clipboard formats

    func testGoogleDocsWrapper() {
        let html = """
        <meta charset="utf-8"><b style="font-weight:normal;" id="docs-internal-guid-1234"><p dir="ltr"><span style="font-weight:700;">Bold</span><span style="font-weight:400;"> text and </span><span style="font-style:italic;">italic</span></p><ul><li dir="ltr"><p dir="ltr"><span>item</span></p></li></ul></b>
        """
        XCTAssertEqual(md(html), "**Bold** text and *italic*\n\n- item")
    }

    func testChatStyleAnswer() {
        let html = "<h2>Steps</h2><ol><li><p>Run <code>swift build</code></p></li><li><p>Open the <strong>app</strong></p></li></ol><pre><code class=\"language-sh\">open App.app</code></pre>"
        XCTAssertEqual(md(html), "## Steps\n\n1. Run `swift build`\n2. Open the **app**\n\n```sh\nopen App.app\n```")
    }

    /// The "Try the two modes" example from the README.
    func testReadmeExample() {
        let html = """
        <h3>Release checklist</h3>
        <p>Ship <strong>version 1.2</strong> after these steps:</p>
        <ol>
          <li>Run the <em>unit tests</em></li>
          <li>Read the <a href="https://www.swift.org/documentation/">Swift docs</a>
            <ul><li>then build the app</li></ul>
          </li>
        </ol>
        """
        XCTAssertEqual(md(html), """
        ### Release checklist

        Ship **version 1.2** after these steps:

        1. Run the *unit tests*
        2. Read the [Swift docs](https://www.swift.org/documentation/)
           - then build the app
        """)
    }

    func testPlainTextPassesThrough() {
        XCTAssertEqual(md("just text"), "just text")
    }
}

final class CapturePlannerTests: XCTestCase {
    func testPlainTextMode() {
        XCTAssertEqual(CapturePlanner.plan(decision: .copy("x"), mode: .plainText, fallbackAllowed: true), .writePlain("x"))
        XCTAssertEqual(CapturePlanner.plan(decision: .skip(.empty), mode: .plainText, fallbackAllowed: true), .sendCopyKeystroke)
        XCTAssertEqual(CapturePlanner.plan(decision: .skip(.empty), mode: .plainText, fallbackAllowed: false), CaptureAction.none)
        XCTAssertEqual(CapturePlanner.plan(decision: .skip(.duplicate), mode: .plainText, fallbackAllowed: true), CaptureAction.none)
    }

    func testMarkdownModeUsesCmdCToGetFormatting() {
        XCTAssertEqual(CapturePlanner.plan(decision: .copy("x"), mode: .markdown, fallbackAllowed: true), .sendCopyKeystroke)
        XCTAssertEqual(CapturePlanner.plan(decision: .skip(.duplicate), mode: .markdown, fallbackAllowed: true), .sendCopyKeystroke)
        // Where Cmd+C isn't allowed (e.g. Finder), fall back to the plain selection.
        XCTAssertEqual(CapturePlanner.plan(decision: .copy("x"), mode: .markdown, fallbackAllowed: false), .writePlain("x"))
    }

    func testSecretsAreNeverCopiedInAnyMode() {
        for mode in CopyMode.allCases {
            for reason in [SkipReason.excludedApp, .secureField, .tooLong] {
                XCTAssertEqual(CapturePlanner.plan(decision: .skip(reason), mode: mode, fallbackAllowed: true), CaptureAction.none)
            }
        }
    }
}
