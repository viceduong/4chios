import ChanCore
import SwiftUI

/// Renders the Markdown a language model writes.
///
/// Not `Text(string)`: SwiftUI parses Markdown only for string *literals*, so
/// text arriving in a `String` variable showed its own asterisks and hashes.
/// `AttributedString(markdown:)` parses it but discards block structure, so the
/// blocks are parsed in ChanCore and styled here.
///
/// Styling goes through `Text(AttributedString)` rather than a bridged text view.
/// A UIKit view has to be told its width before it can say its height, and the
/// two are measured in the wrong order often enough that it clipped the last line
/// of every answer. `Text` wraps and sizes itself, so there is no measurement to
/// get wrong.
///
/// Two consequences of that choice, both deliberate: an inline link is styled and
/// tappable, but emphasis runs share one `Text` so a tap opens the link rather
/// than the paragraph; and a wrapped list item lines up under its marker instead
/// of under its text, since SwiftUI has no hanging indent.
public struct MarkdownText: View {
    private let blocks: [MarkdownBlock]
    private let fontSize: CGFloat

    @Environment(\.chanTheme) private var theme

    public init(_ markdown: String, fontSize: CGFloat) {
        self.blocks = MarkdownDocument.parse(markdown)
        self.fontSize = fontSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: max(6, fontSize * 0.5)) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, index == 0 ? 0 : spacingBefore(block))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Blocks

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let spans):
            blockText(spans, size: fontSize, weight: .regular, color: theme.primaryText)

        case .heading(let level, let spans):
            blockText(
                spans,
                size: headingSize(level),
                weight: .semibold,
                color: theme.primaryText
            )

        case .bullet(let depth, let spans):
            listRow(marker: "•", depth: depth, spans: spans)

        case .numbered(let depth, let marker, let spans):
            listRow(marker: marker, depth: depth, spans: spans)

        case .quote(let spans):
            HStack(alignment: .top, spacing: ChanSpacing.s) {
                Capsule()
                    .fill(theme.accent.opacity(0.6))
                    .frame(width: 3)
                blockText(
                    spans,
                    size: fontSize,
                    weight: .regular,
                    color: theme.secondaryText,
                    italic: true
                )
            }

        case .code(let code):
            Text(code)
                .font(.system(size: max(fontSize - 1, 10), design: .monospaced))
                .foregroundColor(theme.primaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(ChanSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: ChanRadius.small, style: .continuous))

        case .rule:
            Rectangle()
                .fill(theme.elevated)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
    }

    /// One list line. The marker gets a fixed column so markers and numbers line
    /// up down the list, and a wrapped line lands under the marker rather than
    /// under the text - SwiftUI cannot hang an indent.
    private func listRow(marker: String, depth: Int, spans: [MarkdownSpan]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ChanSpacing.s) {
            Text(marker)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(theme.secondaryText)
                .frame(minWidth: 16, alignment: .leading)
            blockText(spans, size: fontSize, weight: .regular, color: theme.primaryText)
        }
        .padding(.leading, CGFloat(depth) * 16)
    }

    private func blockText(
        _ spans: [MarkdownSpan],
        size: CGFloat,
        weight: Font.Weight,
        color: Color,
        italic: Bool = false
    ) -> some View {
        Text(attributed(spans, size: size, weight: weight, italic: italic))
            .font(.system(size: size, weight: weight))
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize * 1.35
        case 2: return fontSize * 1.2
        case 3: return fontSize * 1.1
        default: return fontSize
        }
    }

    private func spacingBefore(_ block: MarkdownBlock) -> CGFloat {
        if case .heading = block { return max(8, fontSize * 0.7) }
        return 0
    }

    // MARK: - Inline

    /// Emphasis, code and links, as attributes on one string.
    ///
    /// Strikethrough is parsed but not drawn: the obvious attribute for it is not
    /// available at this deployment target, and struck-through model output is
    /// rare enough that plain text is the better trade than a second renderer.
    private func attributed(
        _ spans: [MarkdownSpan],
        size: CGFloat,
        weight: Font.Weight,
        italic: Bool = false
    ) -> AttributedString {
        var output = AttributedString()

        for span in spans {
            var piece = AttributedString(span.text)

            // Italic is applied to the font rather than the view: View.italic()
            // is iOS 16, Font.italic() is not.
            var font = Font.system(size: size, weight: weight)
            if italic || span.italic { font = font.italic() }
            if span.bold { font = .system(size: size, weight: .semibold) }
            if case .code = span.kind { font = .system(size: max(size - 1, 10), design: .monospaced) }
            piece.font = font

            switch span.kind {
            case .code:
                piece.backgroundColor = theme.elevated
            case .link(let url):
                if let url {
                    piece.link = url
                    piece.foregroundColor = theme.accent
                }
            case .text:
                break
            }

            output.append(piece)
        }

        return output
    }
}
