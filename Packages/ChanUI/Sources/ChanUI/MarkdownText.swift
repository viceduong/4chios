import ChanCore
import SwiftUI
import UIKit

/// Renders the Markdown a language model writes.
///
/// Not `Text(...)`: SwiftUI parses Markdown only for string *literals*, so text
/// arriving in a `String` variable showed its own asterisks and hashes verbatim.
/// `AttributedString(markdown:)` parses it but discards block structure -
/// headings flatten, list markers vanish - and its inline attributes differ
/// across OS versions.
///
/// So this takes the same route as the post renderer: build an
/// `NSAttributedString` and show it in a non-scrolling text view. That keeps
/// headings, hanging-indented lists, fenced code and tappable links all working
/// on iOS 15, where the Foundation attributes are long established.
public struct MarkdownText: View {
    private let blocks: [MarkdownBlock]
    private let fontSize: CGFloat

    public init(_ markdown: String, fontSize: CGFloat) {
        self.blocks = MarkdownDocument.parse(markdown)
        self.fontSize = fontSize
    }

    public var body: some View {
        // The width constraint lives here rather than at each call site: a text
        // view asked to size itself with no bounded width reports the width of its
        // longest line, which is what let the text run off the screen.
        MarkdownTextView(blocks: blocks, fontSize: fontSize)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTextView: UIViewRepresentable {
    let blocks: [MarkdownBlock]
    let fontSize: CGFloat

    @Environment(\.chanTheme) private var theme

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.adjustsFontForContentSizeCategory = true
        view.isSelectable = true
        view.textContainer.widthTracksTextView = true
        // Vertical: take the text's own height and never less.
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.setContentHuggingPriority(.required, for: .vertical)
        // Horizontal: claim no width of our own, so the width SwiftUI proposes is
        // what the text wraps inside.
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.linkTextAttributes = [.foregroundColor: UIColor(theme.link)]
        view.attributedText = MarkdownRenderer(theme: theme, fontSize: fontSize)
            .attributedString(for: blocks)
    }
}

/// Turns parsed Markdown blocks into styled text.
struct MarkdownRenderer {
    let theme: ChanTheme
    let fontSize: CGFloat

    // MARK: - Metrics

    private var baseFont: UIFont { .systemFont(ofSize: fontSize) }
    private var blockSpacing: CGFloat { max(6, fontSize * 0.5) }
    private var lineSpacing: CGFloat { max(2, fontSize * 0.18) }
    private var indentStep: CGFloat { 16 }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize * 1.35
        case 2: return fontSize * 1.2
        case 3: return fontSize * 1.1
        default: return fontSize
        }
    }

    // MARK: - Document

    func attributedString(for blocks: [MarkdownBlock]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            output.append(self.block(block, isLast: index == blocks.count - 1))
        }
        return output
    }

    private func block(_ block: MarkdownBlock, isLast: Bool) -> NSAttributedString {
        // The terminator carries the paragraph style, which is what produces the
        // spacing between blocks.
        let terminator = isLast ? "" : "\n"

        switch block {
        case .paragraph(let spans):
            return line(
                spans,
                style: paragraph(),
                font: baseFont,
                color: UIColor(theme.primaryText),
                terminator: terminator
            )

        case .heading(let level, let spans):
            let size = headingSize(level)
            let style = paragraph(
                spaceBefore: blockSpacing * 1.4,
                spaceAfter: blockSpacing * 0.4
            )
            return line(
                spans,
                style: style,
                font: .systemFont(ofSize: size, weight: .semibold),
                color: UIColor(theme.primaryText),
                terminator: terminator
            )

        case .bullet(let depth, let spans):
            return listItem(
                marker: "•",
                depth: depth,
                spans: spans,
                terminator: terminator
            )

        case .numbered(let depth, let marker, let spans):
            return listItem(
                marker: marker,
                depth: depth,
                spans: spans,
                terminator: terminator
            )

        case .quote(let spans):
            let style = paragraph()
            style.firstLineHeadIndent = 0
            style.headIndent = 12
            style.lineSpacing = lineSpacing

            let result = NSMutableAttributedString()
            result.append(
                NSAttributedString(
                    string: "▎ ",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: UIColor(theme.accent),
                    ]
                )
            )
            append(spans, to: result, font: baseFont, color: UIColor(theme.secondaryText))
            result.append(NSAttributedString(string: terminator, attributes: [.font: baseFont]))
            result.addAttribute(
                .paragraphStyle,
                value: style,
                range: NSRange(location: 0, length: result.length)
            )
            return result

        case .code(let code):
            let style = paragraph()
            style.lineSpacing = 2
            return NSAttributedString(
                string: code + terminator,
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: max(fontSize - 1, 10), weight: .regular),
                    .foregroundColor: UIColor(theme.primaryText),
                    .backgroundColor: UIColor(theme.elevated),
                    .paragraphStyle: style,
                ]
            )

        case .rule:
            return NSAttributedString(
                string: String(repeating: "─", count: 30) + terminator,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: UIColor(theme.separator),
                    .paragraphStyle: paragraph(spaceBefore: blockSpacing, spaceAfter: blockSpacing),
                ]
            )
        }
    }

    // MARK: - Pieces

    private func line(
        _ spans: [MarkdownSpan],
        style: NSParagraphStyle,
        font: UIFont,
        color: UIColor,
        terminator: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        append(spans, to: result, font: font, color: color)
        result.append(NSAttributedString(string: terminator, attributes: [.font: font]))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// A list item hangs on a tab stop, so a wrapped line lines up under the text
    /// rather than under the marker.
    private func listItem(
        marker: String,
        depth: Int,
        spans: [MarkdownSpan],
        terminator: String
    ) -> NSAttributedString {
        let indent = CGFloat(depth) * indentStep
        let markerWidth = max(18, CGFloat(marker.count) * fontSize * 0.62)

        let style = paragraph()
        style.firstLineHeadIndent = indent
        style.headIndent = indent + markerWidth
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
        style.paragraphSpacing = blockSpacing * 0.35

        let result = NSMutableAttributedString()
        result.append(
            NSAttributedString(
                string: marker + "\t",
                attributes: [
                    .font: baseFont,
                    .foregroundColor: UIColor(theme.secondaryText),
                ]
            )
        )
        append(spans, to: result, font: baseFont, color: UIColor(theme.primaryText))
        result.append(NSAttributedString(string: terminator, attributes: [.font: baseFont]))
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    private func append(
        _ spans: [MarkdownSpan],
        to output: NSMutableAttributedString,
        font: UIFont,
        color: UIColor
    ) {
        for span in spans {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: styled(span, base: font),
                .foregroundColor: color,
            ]

            if span.strikethrough {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }

            switch span.kind {
            case .code:
                attributes[.backgroundColor] = UIColor(theme.elevated)
            case .link(let url):
                if let url {
                    attributes[.link] = url
                    attributes[.foregroundColor] = UIColor(theme.link)
                }
            case .text:
                break
            }

            output.append(NSAttributedString(string: span.text, attributes: attributes))
        }
    }

    private func styled(_ span: MarkdownSpan, base: UIFont) -> UIFont {
        if case .code = span.kind {
            return .monospacedSystemFont(ofSize: max(base.pointSize - 1, 10), weight: .regular)
        }

        var font = base
        if span.bold {
            font = .systemFont(ofSize: base.pointSize, weight: .semibold)
        }
        if span.italic {
            let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: 0)
            }
        }
        return font
    }

    private func paragraph(spaceBefore: CGFloat = 0, spaceAfter: CGFloat? = nil) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spaceBefore
        style.paragraphSpacing = spaceAfter ?? blockSpacing
        style.lineSpacing = lineSpacing
        return style
    }
}
