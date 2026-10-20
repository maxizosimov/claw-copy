import Foundation

/// Converts the HTML that apps put on the clipboard into Markdown.
///
/// Deliberately small and strict: a hand-written tokenizer and renderer that understand basic
/// text structure (headings, paragraphs, emphasis, code, links, lists, quotes, tables) and drop
/// everything else. It never loads, executes or renders anything: no WebKit, no
/// `NSAttributedString` HTML import (which can fetch remote resources), no scripts, styles or
/// images. Only `http`, `https` and `mailto` links survive.
public enum HTMLToMarkdown {
    /// Larger clipboard HTML is left alone rather than converted.
    public static let maxInputBytes = 2_000_000
    /// Deeper nesting is flattened, which bounds recursion.
    public static let maxDepth = 128

    /// Returns `nil` when there is nothing to convert or the input is too large.
    public static func convert(_ html: String) -> String? {
        guard html.utf8.count <= maxInputBytes else { return nil }
        let root = HTMLTreeBuilder.build(HTMLTokenizer.tokenize(html), maxDepth: maxDepth)
        let markdown = MarkdownRenderer().renderDocument(root)
        return markdown.isEmpty ? nil : markdown
    }
}

// MARK: - Tokenizer

enum HTMLToken: Equatable {
    case text(String)
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    case end(name: String)
}

enum HTMLTokenizer {
    /// Elements whose content is skipped entirely, never parsed or kept.
    static let skippedElements: Set<String> = [
        "script", "style", "noscript", "template", "title", "head", "textarea", "xmp",
        "iframe", "noembed", "noframes", "object", "svg", "math", "canvas", "select",
    ]

    static func tokenize(_ html: String) -> [HTMLToken] {
        let s = Array(html.unicodeScalars)
        var tokens: [HTMLToken] = []
        var text = String.UnicodeScalarView()
        var i = 0

        func flushText() {
            guard !text.isEmpty else { return }
            tokens.append(.text(decodeEntities(String(text))))
            text = String.UnicodeScalarView()
        }

        while i < s.count {
            guard s[i] == "<" else {
                text.append(s[i])
                i += 1
                continue
            }
            if matches(s, i, "<!--") {
                flushText()
                i = find(s, "-->", from: i + 4).map { $0 + 3 } ?? s.count
                continue
            }
            if i + 1 < s.count, s[i + 1] == "!" || s[i + 1] == "?" {
                flushText()
                i = find(s, ">", from: i).map { $0 + 1 } ?? s.count
                continue
            }
            let token: HTMLToken
            switch parseTag(s, i) {
            case .notATag:
                text.append(s[i]) // a literal "<"
                i += 1
                continue
            case .unterminated:
                // A tag that runs off the end: the rest is text. Stopping here (instead of
                // retrying at every later "<") keeps hostile input linear-time.
                text.append(contentsOf: s[i...])
                i = s.count
                continue
            case let .tag(parsed, next):
                token = parsed
                i = next
            }
            flushText()
            if case let .start(name, _, selfClosing) = token, skippedElements.contains(name) {
                if !selfClosing {
                    i = find(s, "</" + name, from: i, caseInsensitive: true)
                        .flatMap { find(s, ">", from: $0) }
                        .map { $0 + 1 } ?? s.count
                }
                continue
            }
            if case let .end(name) = token, skippedElements.contains(name) { continue }
            tokens.append(token)
        }
        flushText()
        return tokens
    }

    private enum TagParse {
        case tag(HTMLToken, Int)
        case notATag
        case unterminated
    }

    private static func parseTag(_ s: [Unicode.Scalar], _ start: Int) -> TagParse {
        var i = start + 1
        var isEnd = false
        if i < s.count, s[i] == "/" {
            isEnd = true
            i += 1
        }
        guard i < s.count, isASCIILetter(s[i]) else { return .notATag }
        var name = ""
        while i < s.count, isNameCharacter(s[i]) {
            name.unicodeScalars.append(lowercased(s[i]))
            i += 1
        }
        if isEnd {
            guard let close = find(s, ">", from: i) else { return .unterminated }
            return .tag(.end(name: name), close + 1)
        }

        var attributes: [String: String] = [:]
        var selfClosing = false
        while true {
            while i < s.count, isSpace(s[i]) { i += 1 }
            guard i < s.count else { return .unterminated }
            if s[i] == ">" {
                i += 1
                break
            }
            if s[i] == "/" {
                i += 1
                if i < s.count, s[i] == ">" {
                    selfClosing = true
                    i += 1
                    break
                }
                continue
            }
            var attributeName = ""
            while i < s.count, !isSpace(s[i]), s[i] != "=", s[i] != ">", s[i] != "/" {
                attributeName.unicodeScalars.append(lowercased(s[i]))
                i += 1
            }
            while i < s.count, isSpace(s[i]) { i += 1 }
            var value = ""
            if i < s.count, s[i] == "=" {
                i += 1
                while i < s.count, isSpace(s[i]) { i += 1 }
                guard i < s.count else { return .unterminated }
                var raw = String.UnicodeScalarView()
                if s[i] == "\"" || s[i] == "'" {
                    let quote = s[i]
                    i += 1
                    while i < s.count, s[i] != quote {
                        raw.append(s[i])
                        i += 1
                    }
                    guard i < s.count else { return .unterminated }
                    i += 1
                } else {
                    while i < s.count, !isSpace(s[i]), s[i] != ">" {
                        raw.append(s[i])
                        i += 1
                    }
                }
                value = String(raw)
            }
            if !attributeName.isEmpty, attributes[attributeName] == nil {
                attributes[attributeName] = decodeEntities(value)
            }
        }
        return .tag(.start(name: name, attributes: attributes, selfClosing: selfClosing), i)
    }

    // MARK: Entities

    static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "ensp": " ", "emsp": " ", "thinsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "bull": "•", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»",
        "copy": "©", "reg": "®", "trade": "™", "deg": "°", "times": "×", "divide": "÷",
        "plusmn": "±", "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§",
        "para": "¶", "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔",
        "check": "✓", "zwj": "\u{200D}", "zwnj": "\u{200C}", "shy": "\u{00AD}",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let s = Array(text.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            if s[i] == "&", let found = entity(s, i) {
                out.append(contentsOf: found.0.unicodeScalars)
                i = found.1
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return String(out)
    }

    private static func entity(_ s: [Unicode.Scalar], _ start: Int) -> (String, Int)? {
        var i = start + 1
        var body = ""
        while i < s.count, s[i] != ";" {
            if i - start > 32 || isSpace(s[i]) || s[i] == "&" || s[i] == "<" { return nil }
            body.unicodeScalars.append(s[i])
            i += 1
        }
        guard i < s.count, !body.isEmpty else { return nil }
        let next = i + 1
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value else { return nil }
            if value == 0xA0 { return (" ", next) }
            guard value != 0, let scalar = Unicode.Scalar(value) else { return ("\u{FFFD}", next) }
            return (String(Character(scalar)), next)
        }
        guard let named = namedEntities[body] else { return nil }
        return (named, next)
    }

    // MARK: Scanning helpers

    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}"
    }

    private static func isASCIILetter(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 0x41 && c.value <= 0x5A) || (c.value >= 0x61 && c.value <= 0x7A)
    }

    private static func isNameCharacter(_ c: Unicode.Scalar) -> Bool {
        isASCIILetter(c) || (c.value >= 0x30 && c.value <= 0x39) || c == "-" || c == ":" || c == "_"
    }

    private static func lowercased(_ c: Unicode.Scalar) -> Unicode.Scalar {
        guard c.value >= 0x41, c.value <= 0x5A, let lower = Unicode.Scalar(c.value + 0x20) else { return c }
        return lower
    }

    private static func matches(_ s: [Unicode.Scalar], _ i: Int, _ literal: String, caseInsensitive: Bool = false) -> Bool {
        var j = i
        for c in literal.unicodeScalars {
            guard j < s.count else { return false }
            let a = caseInsensitive ? lowercased(s[j]) : s[j]
            let b = caseInsensitive ? lowercased(c) : c
            if a != b { return false }
            j += 1
        }
        return true
    }

    private static func find(_ s: [Unicode.Scalar], _ literal: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
        guard let first = literal.unicodeScalars.first else { return nil }
        var i = start
        while i < s.count {
            if (caseInsensitive ? lowercased(s[i]) == lowercased(first) : s[i] == first),
               matches(s, i, literal, caseInsensitive: caseInsensitive) {
                return i
            }
            i += 1
        }
        return nil
    }
}

// MARK: - Tree

final class HTMLNode {
    let name: String
    let attributes: [String: String]
    let text: String?
    var children: [HTMLNode] = []

    init(name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
        self.text = nil
    }

    init(text: String) {
        self.name = "#text"
        self.attributes = [:]
        self.text = text
    }

    var isText: Bool { text != nil }
}

/// Builds a forgiving tree: unclosed tags are closed at the end, stray end tags are ignored,
/// and the usual implied closes (`<li>`, `<p>`, table cells) are applied.
enum HTMLTreeBuilder {
    static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr",
    ]

    static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
        "hr", "main", "nav", "ol", "p", "pre", "section", "table", "ul",
    ]

    static func build(_ tokens: [HTMLToken], maxDepth: Int) -> HTMLNode {
        let root = HTMLNode(name: "#root")
        var stack = [root]
        for token in tokens {
            switch token {
            case .text(let text):
                stack[stack.count - 1].children.append(HTMLNode(text: text))
            case let .start(name, attributes, selfClosing):
                applyImpliedCloses(before: name, &stack)
                let node = HTMLNode(name: name, attributes: attributes)
                stack[stack.count - 1].children.append(node)
                if !selfClosing, !voidElements.contains(name), stack.count < maxDepth {
                    stack.append(node)
                }
            case .end(let name):
                if let index = stack.lastIndex(where: { $0.name == name }), index > 0 {
                    stack.removeSubrange(index...)
                }
            }
        }
        return root
    }

    private static func applyImpliedCloses(before name: String, _ stack: inout [HTMLNode]) {
        if closesParagraph.contains(name), stack.last?.name == "p" {
            stack.removeLast()
        }
        switch name {
        case "li": close(["li"], until: ["ul", "ol", "menu"], &stack)
        case "dt", "dd": close(["dt", "dd"], until: ["dl"], &stack)
        case "tr": close(["tr"], until: ["table", "thead", "tbody", "tfoot"], &stack)
        case "td", "th": close(["td", "th"], until: ["tr", "table"], &stack)
        case "thead", "tbody", "tfoot": close(["thead", "tbody", "tfoot"], until: ["table"], &stack)
        default: break
        }
    }

    private static func close(_ names: Set<String>, until boundary: Set<String>, _ stack: inout [HTMLNode]) {
        var i = stack.count - 1
        while i > 0 {
            let name = stack[i].name
            if names.contains(name) {
                stack.removeSubrange(i...)
                return
            }
            if boundary.contains(name) { return }
            i -= 1
        }
    }
}

// MARK: - Renderer

struct MarkdownRenderer {
    struct Context {
        var bold = false
        var italic = false
        var strike = false
        var inLink = false
    }

    static let blockElements: Set<String> = [
        "address", "article", "aside", "blockquote", "body", "caption", "center", "dd", "details",
        "dialog", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "html", "li", "main", "nav",
        "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead",
        "tr", "ul",
    ]

    /// Rendered as nothing.
    static let ignoredElements: Set<String> = [
        "area", "audio", "base", "button", "col", "colgroup", "embed", "link", "map", "meta",
        "option", "param", "picture", "source", "track", "video", "wbr",
    ]

    static let headingLevels: [String: Int] = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]

    func renderDocument(_ root: HTMLNode) -> String {
        var markdown = renderBlocks(root.children, Context()).joined(separator: "\n\n")
        while markdown.contains("\n\n\n") {
            markdown = markdown.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Blocks

    func renderBlocks(_ nodes: [HTMLNode], _ ctx: Context) -> [String] {
        var blocks: [String] = []
        var inline = ""
        func flush() {
            let paragraph = Self.finishParagraph(inline)
            if !paragraph.isEmpty { blocks.append(paragraph) }
            inline = ""
        }
        for node in nodes {
            if !node.isText, Self.blockElements.contains(node.name) || Self.containsBlock(node) {
                flush()
                blocks.append(contentsOf: renderBlock(node, ctx))
            } else {
                inline += renderInline(node, ctx)
            }
        }
        flush()
        return blocks
    }

    private func renderBlock(_ node: HTMLNode, _ ctx: Context) -> [String] {
        if let level = Self.headingLevels[node.name] {
            let text = Self.singleLine(renderInlineChildren(node, ctx))
            return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
        }
        switch node.name {
        case "ul":
            return renderList(node, ordered: false, ctx)
        case "ol":
            return renderList(node, ordered: true, ctx)
        case "li":
            let body = renderBlocks(node.children, ctx).joined(separator: "\n")
            return body.isEmpty ? [] : ["- " + Self.indent(body, by: 2, skippingFirstLine: true)]
        case "blockquote":
            let body = renderBlocks(node.children, ctx).joined(separator: "\n\n")
            guard !body.isEmpty else { return [] }
            return [body.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }
                .joined(separator: "\n")]
        case "pre":
            return renderCodeBlock(node)
        case "hr":
            return ["---"]
        case "table":
            return renderTable(node, ctx)
        default:
            // div, p, section, … and inline elements that wrap blocks (e.g. Google Docs' <b>).
            return renderBlocks(node.children, ctx)
        }
    }

    private func renderList(_ node: HTMLNode, ordered: Bool, _ ctx: Context) -> [String] {
        var number = ordered ? max(0, Int(node.attributes["start"] ?? "") ?? 1) : 1
        var items: [String] = []
        var lastMarkerWidth = 2
        for child in node.children {
            if let text = child.text, text.allSatisfy(\.isWhitespace) { continue }
            if child.name == "ul" || child.name == "ol", !items.isEmpty {
                // A list directly inside a list belongs to the previous item.
                let nested = renderBlocks([child], ctx).joined(separator: "\n")
                if !nested.isEmpty {
                    items[items.count - 1] += "\n" + Self.indent(nested, by: lastMarkerWidth, skippingFirstLine: false)
                }
                continue
            }
            let body = renderBlocks(child.name == "li" ? child.children : [child], ctx).joined(separator: "\n")
            guard !body.isEmpty else { continue }
            let marker = ordered ? "\(number). " : "- "
            if ordered { number += 1 }
            lastMarkerWidth = marker.count
            items.append(marker + Self.indent(body, by: marker.count, skippingFirstLine: true))
        }
        return items.isEmpty ? [] : [items.joined(separator: "\n")]
    }

    private func renderCodeBlock(_ node: HTMLNode) -> [String] {
        var code = Self.textContent(node).replacingOccurrences(of: "\r\n", with: "\n")
        if code.hasPrefix("\n") { code.removeFirst() }
        while code.hasSuffix("\n") { code.removeLast() }
        guard !code.allSatisfy(\.isWhitespace) else { return [] }
        let fence = String(repeating: "`", count: max(3, Self.longestRun(of: "`", in: code) + 1))
        return [fence + Self.codeLanguage(node) + "\n" + code + "\n" + fence]
    }

    private func renderTable(_ node: HTMLNode, _ ctx: Context) -> [String] {
        var rows: [[String]] = []
        var caption: [String] = []
        func collect(_ parent: HTMLNode) {
            for child in parent.children {
                switch child.name {
                case "tr":
                    rows.append(child.children
                        .filter { $0.name == "td" || $0.name == "th" }
                        .map { Self.tableCell(renderInlineChildren($0, ctx)) })
                case "thead", "tbody", "tfoot":
                    collect(child)
                case "caption":
                    caption.append(contentsOf: renderBlocks(child.children, ctx))
                default:
                    break
                }
            }
        }
        collect(node)
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return caption }
        let padded = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        func line(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }
        var lines = [line(padded[0]), line(Array(repeating: "---", count: columns))]
        lines += padded.dropFirst().map(line)
        return caption + [lines.joined(separator: "\n")]
    }

    // MARK: Inline

    private func renderInlineChildren(_ node: HTMLNode, _ ctx: Context) -> String {
        node.children.map { renderInline($0, ctx) }.joined()
    }

    private func renderInline(_ node: HTMLNode, _ ctx: Context) -> String {
        if let text = node.text {
            return Self.escape(Self.collapseWhitespace(text))
        }
        let name = node.name
        switch name {
        case "br":
            return "\n"
        case "img":
            return Self.escape(Self.collapseWhitespace(node.attributes["alt"] ?? ""))
        case "input":
            guard node.attributes["type"]?.lowercased() == "checkbox" else { return "" }
            return node.attributes["checked"] != nil ? "[x] " : "[ ] "
        case "code", "kbd", "samp", "tt":
            return Self.inlineCode(Self.collapseWhitespace(Self.textContent(node)))
        case "a":
            var inner = ctx
            inner.inLink = true
            let content = renderInlineChildren(node, inner)
            guard !ctx.inLink, let href = node.attributes["href"].flatMap(Self.safeURL) else { return content }
            return Self.surround(content, before: "[", after: "](" + href + ")")
        default:
            break
        }
        if Self.ignoredElements.contains(name) { return "" }

        let style = InlineStyle(node.attributes["style"])
        var inner = ctx
        var markers: [String] = []
        let bold = (name == "b" || name == "strong") ? style.bold != false : style.bold == true
        if bold, !ctx.bold {
            markers.append("**")
            inner.bold = true
        }
        let italic = ["em", "i", "cite", "dfn", "var"].contains(name) ? style.italic != false : style.italic == true
        if italic, !ctx.italic {
            markers.append("*")
            inner.italic = true
        }
        if ["del", "s", "strike"].contains(name) || style.strike, !ctx.strike {
            markers.append("~~")
            inner.strike = true
        }
        var content = renderInlineChildren(node, inner)
        for marker in markers.reversed() {
            content = Self.surround(content, before: marker, after: marker)
        }
        // A block element flattened into a line (e.g. inside a table cell) stays separated.
        return Self.blockElements.contains(name) ? " " + content + " " : content
    }

    struct InlineStyle {
        var bold: Bool? = nil
        var italic: Bool? = nil
        var strike = false

        init(_ css: String?) {
            guard let css else { return }
            let compact = css.lowercased().filter { !$0.isWhitespace }
            for declaration in compact.split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let value = String(parts[1])
                switch parts[0] {
                case "font-weight":
                    if value == "bold" || value == "bolder" {
                        bold = true
                    } else if value == "normal" || value == "lighter" {
                        bold = false
                    } else if let weight = Int(value) {
                        bold = weight >= 600
                    }
                case "font-style":
                    if value == "italic" || value == "oblique" {
                        italic = true
                    } else if value == "normal" {
                        italic = false
                    }
                case "text-decoration", "text-decoration-line":
                    if value.contains("line-through") { strike = true }
                default:
                    break
                }
            }
        }
    }

    // MARK: Helpers

    static func containsBlock(_ node: HTMLNode) -> Bool {
        node.children.contains { !$0.isText && (blockElements.contains($0.name) || containsBlock($0)) }
    }

    static func textContent(_ node: HTMLNode) -> String {
        if let text = node.text { return text }
        if node.name == "br" { return "\n" }
        return node.children.map(textContent).joined()
    }

    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    /// Escapes characters that would otherwise turn plain text into Markdown formatting.
    static func escape(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        for (i, ch) in chars.enumerated() {
            switch ch {
            case "\\", "`", "*", "[", "]", "<":
                out.append("\\")
            case "_":
                // snake_case stays readable; only underscores that could start/end emphasis.
                let wordBefore = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                let wordAfter = i + 1 < chars.count && (chars[i + 1].isLetter || chars[i + 1].isNumber)
                if !(wordBefore && wordAfter) { out.append("\\") }
            default:
                break
            }
            out.append(ch)
        }
        return out
    }

    /// Wraps `content` in markers, keeping its leading/trailing spaces outside them.
    static func surround(_ content: String, before: String, after: String) -> String {
        let leading = content.prefix { $0 == " " || $0 == "\n" }
        let rest = content.dropFirst(leading.count)
        let trailingCount = rest.reversed().prefix { $0 == " " || $0 == "\n" }.count
        let core = rest.dropLast(trailingCount)
        guard !core.isEmpty else { return content }
        return String(leading) + before + String(core) + after + String(rest.suffix(trailingCount))
    }

    static func inlineCode(_ code: String) -> String {
        guard !code.allSatisfy(\.isWhitespace) else { return code }
        let fence = String(repeating: "`", count: longestRun(of: "`", in: code) + 1)
        let pad = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
        return fence + pad + code + pad + fence
    }

    static func longestRun(of character: Character, in text: String) -> Int {
        var longest = 0
        var current = 0
        for ch in text {
            current = ch == character ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    static func codeLanguage(_ pre: HTMLNode) -> String {
        let classes = [pre.attributes["class"]] + pre.children.filter { $0.name == "code" }.map { $0.attributes["class"] }
        for case let list? in classes {
            for name in list.split(whereSeparator: \.isWhitespace) {
                for prefix in ["language-", "lang-"] where name.hasPrefix(prefix) {
                    let language = name.dropFirst(prefix.count).filter {
                        $0.isASCII && ($0.isLetter || $0.isNumber || "+#._-".contains($0))
                    }
                    if !language.isEmpty { return String(language.prefix(30)) }
                }
            }
        }
        return ""
    }

    /// Only links that are safe to click survive; anything else (javascript:, data:, file:, …)
    /// keeps its text but loses the link.
    static let allowedLinkSchemes: Set<String> = ["http", "https", "mailto"]

    static func safeURL(_ raw: String) -> String? {
        let cleaned = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
        })).trimmingCharacters(in: .whitespaces)
        guard let colon = cleaned.firstIndex(of: ":"),
              allowedLinkSchemes.contains(cleaned[..<colon].lowercased()) else {
            return nil
        }
        return cleaned
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
            .replacingOccurrences(of: "<", with: "%3C")
            .replacingOccurrences(of: ">", with: "%3E")
    }

    static func singleLine(_ text: String) -> String {
        collapseSpaces(text.replacingOccurrences(of: "\n", with: " ")).trimmingCharacters(in: .whitespaces)
    }

    static func tableCell(_ text: String) -> String {
        singleLine(text).replacingOccurrences(of: "|", with: "\\|")
    }

    static func collapseSpaces(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for ch in text {
            if ch == " " {
                if !lastWasSpace { out.append(ch) }
                lastWasSpace = true
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

    static func indent(_ text: String, by width: Int, skippingFirstLine: Bool) -> String {
        let pad = String(repeating: " ", count: width)
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line in
            (index == 0 && skippingFirstLine) || line.isEmpty ? String(line) : pad + line
        }.joined(separator: "\n")
    }

    /// Tidies an inline run into a paragraph: trims lines and escapes line starts that would
    /// otherwise become headings, quotes or list items.
    static func finishParagraph(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = escapeLineStart(collapseSpaces(String(raw)).trimmingCharacters(in: .whitespaces))
            if line.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    static func escapeLineStart(_ line: String) -> String {
        guard let first = line.first else { return line }
        if first == "#" || first == ">" { return "\\" + line }
        if (first == "-" || first == "+"), line.count == 1 || line.dropFirst().first == " " { return "\\" + line }
        if line.count >= 3, first == "-" || first == "=", line.allSatisfy({ $0 == first || $0 == " " }) {
            return "\\" + line
        }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let rest = line.dropFirst(digits.count)
            if let marker = rest.first, marker == "." || marker == ")", rest.count == 1 || rest.dropFirst().first == " " {
                return String(digits) + "\\" + String(rest)
            }
        }
        return line
    }
}
