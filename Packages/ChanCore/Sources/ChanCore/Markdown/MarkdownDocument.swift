import Foundation

/// A run of inline text with the emphasis that applies to it.
public struct MarkdownSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case text
        case code
        case link(URL?)
    }

    public let text: String
    public let kind: Kind
    public let bold: Bool
    public let italic: Bool
    public let strikethrough: Bool

    public init(
        text: String,
        kind: Kind = .text,
        bold: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false
    ) {
        self.text = text
        self.kind = kind
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
    }

    public var isPlain: Bool {
        kind == .text && !bold && !italic && !strikethrough
    }
}

/// One block of a Markdown document.
///
/// Deliberately a small, explicit set rather than the whole specification: these
/// are the shapes a language model actually emits, and each one has an obvious
/// rendering. Anything unrecognised degrades to a paragraph, which is why a
/// partial implementation is safe here.
public enum MarkdownBlock: Equatable, Sendable {
    case paragraph([MarkdownSpan])
    case heading(level: Int, spans: [MarkdownSpan])
    case bullet(depth: Int, spans: [MarkdownSpan])
    case numbered(depth: Int, marker: String, spans: [MarkdownSpan])
    case quote([MarkdownSpan])
    case code(String)
    case rule

    public var spans: [MarkdownSpan] {
        switch self {
        case .paragraph(let spans), .heading(_, let spans), .bullet(_, let spans),
             .numbered(_, _, let spans), .quote(let spans):
            return spans
        case .code, .rule:
            return []
        }
    }
}

/// Parses the Markdown a language model writes into blocks a view can style.
///
/// The alternative was `AttributedString(markdown:)`, which handles emphasis but
/// loses block structure - headings become plain lines and list items lose their
/// markers - and whose exact behaviour varies by OS version. Parsing it here
/// keeps the result the same everywhere and lets the renderer decide the styling.
public enum MarkdownDocument {
    /// The deepest list nesting that gets its own indentation.
    private static let maximumDepth = 3

    public static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var fence: [String]?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
            paragraph = []
        }

        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(inline(quote.joined(separator: " "))))
            quote = []
        }

        func flushAll() {
            flushParagraph()
            flushQuote()
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // A fence swallows everything until it closes, including markers that
            // would otherwise be emphasis.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let open = fence {
                    blocks.append(.code(open.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushAll()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            if let heading = heading(in: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, spans: inline(heading.text)))
                continue
            }

            // Checked before bullets, since `---` and `- - -` both start with `-`.
            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                continue
            }

            if let item = bullet(in: trimmed) {
                flushParagraph()
                blocks.append(.bullet(depth: depth(of: rawLine), spans: inline(item)))
                continue
            }

            if let item = numbered(in: trimmed) {
                flushParagraph()
                blocks.append(
                    .numbered(depth: depth(of: rawLine), marker: item.marker, spans: inline(item.text))
                )
                continue
            }

            // Wrapped lines are one paragraph, not a line break per line.
            paragraph.append(trimmed)
        }

        flushAll()

        // An unterminated fence is far more likely to be a model that stopped
        // mid-answer than literal backticks, so show what arrived as code.
        if let open = fence {
            blocks.append(.code(open.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - Block recognition

    private static func heading(in line: String) -> (level: Int, text: String)? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func isRule(_ line: String) -> Bool {
        let stripped = line.filter { $0 != " " }
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func bullet(in line: String) -> String? {
        guard let first = line.first, "-*+".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.isEmpty || rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func numbered(in line: String) -> (marker: String, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }

        var rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.isEmpty || rest.first == " " else { return nil }

        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : ("\(digits).", text)
    }

    private static func depth(of rawLine: String) -> Int {
        let indent = rawLine.prefix { $0 == " " || $0 == "\t" }
            .reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(indent / 2, maximumDepth)
    }

    // MARK: - Inline recognition

    /// Splits a line into styled runs.
    ///
    /// Markers are handled as runs rather than one at a time, so `***both***`
    /// opens and closes as a pair instead of leaving a stray asterisk behind. A
    /// marker with no closing partner - a multiplication sign, a footnote dagger
    /// - is left as written rather than italicising the rest of the answer.
    public static func inline(_ text: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var buffer = ""
        var bold = false
        var italic = false
        var strikethrough = false
        var index = text.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            spans.append(
                MarkdownSpan(
                    text: buffer,
                    kind: .text,
                    bold: bold,
                    italic: italic,
                    strikethrough: strikethrough
                )
            )
            buffer = ""
        }

        /// How many of `marker` start here, capped at three.
        func runLength(of marker: Character, at position: String.Index) -> Int {
            var count = 0
            var cursor = position
            while cursor < text.endIndex, text[cursor] == marker, count < 3 {
                count += 1
                cursor = text.index(after: cursor)
            }
            return count
        }

        /// Whether a closing marker exists from this position on.
        ///
        /// Only used to decide whether a marker *opens*; a marker that closes
        /// something already open needs no lookahead.
        func hasCloser(_ marker: Character, from position: String.Index) -> Bool {
            position < text.endIndex && text[position...].contains(marker)
        }

        /// `_` is only a marker at a word boundary, so identifiers such as
        /// `saved_media` survive intact.
        func underscoreIsMarker(at position: String.Index) -> Bool {
            guard position > text.startIndex else { return true }
            let previous = text[text.index(before: position)]
            return !previous.isLetter && !previous.isNumber
        }

        while index < text.endIndex {
            let character = text[index]

            if character == "\\", let next = text.index(index, offsetBy: 1, limitedBy: text.endIndex),
               next < text.endIndex {
                buffer.append(text[next])
                index = text.index(after: next)
                continue
            }

            // Code spans are literal, so emphasis inside them is not parsed.
            if character == "`" {
                let afterTick = text.index(after: index)
                if let close = text[afterTick...].firstIndex(of: "`") {
                    flush()
                    spans.append(MarkdownSpan(text: String(text[afterTick..<close]), kind: .code))
                    index = text.index(after: close)
                    continue
                }
            }

            if character == "[", let link = link(at: index, in: text) {
                flush()
                spans.append(MarkdownSpan(text: link.label, kind: .link(link.url)))
                index = link.next
                continue
            }

            if character == "~", text[index...].hasPrefix("~~") {
                let consumed = text.index(index, offsetBy: 2)
                // Already open means this run closes it, whatever follows.
                if strikethrough || hasCloser("~", from: consumed) {
                    flush()
                    strikethrough.toggle()
                    index = consumed
                    continue
                }
            }

            if character == "*" || character == "_" {
                let usable = character == "*" || underscoreIsMarker(at: index)
                if usable {
                    let count = runLength(of: character, at: index)
                    let consumed = text.index(index, offsetBy: count)

                    // Anything already open is closed by this run before a new
                    // one is opened. Flushing first is what keeps the buffered
                    // text on the style that was in force while it was read.
                    if count >= 2, bold {
                        flush()
                        bold = false
                        if count >= 3 { italic = false }
                        index = consumed
                        continue
                    }
                    if count == 1, italic {
                        flush()
                        italic = false
                        index = consumed
                        continue
                    }
                    if hasCloser(character, from: consumed) {
                        flush()
                        if count >= 2 {
                            bold = true
                            if count >= 3 { italic = true }
                        } else {
                            italic = true
                        }
                        index = consumed
                        continue
                    }
                }
            }

            buffer.append(character)
            index = text.index(after: index)
        }

        flush()
        return spans
    }

    private static func link(
        at start: String.Index,
        in text: String
    ) -> (label: String, url: URL?, next: String.Index)? {
        let afterBracket = text.index(after: start)
        guard let closeBracket = text[afterBracket...].firstIndex(of: "]") else { return nil }

        let afterClose = text.index(after: closeBracket)
        guard afterClose < text.endIndex, text[afterClose] == "(" else { return nil }
        let urlStart = text.index(after: afterClose)
        guard let closeParen = text[urlStart...].firstIndex(of: ")") else { return nil }

        let label = String(text[afterBracket..<closeBracket])
        let rawURL = String(text[urlStart..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return nil }

        return (label, URL(string: rawURL), text.index(after: closeParen))
    }
}
