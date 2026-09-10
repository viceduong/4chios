import ChanCore
import SwiftUI
import UIKit

public extension NSAttributedString.Key {
    /// Marks a run as a hidden spoiler and stores its run index.
    static let chanSpoiler = NSAttributedString.Key("com.viceduong.ch4ios.spoiler")
}

/// Converts the platform-agnostic `PostBody` into a UIKit attributed string.
///
/// This is the only place that maps post semantics to concrete colors and fonts,
/// so a theme change never touches parsing.
public struct PostBodyRenderer {
    public let theme: ChanTheme
    public let fontSize: CGFloat
    /// Run indices whose spoilers the user has revealed.
    public let revealedSpoilers: Set<Int>
    /// `>>N` links that deserve a suffix, e.g. `(OP)` or `(You)`.
    public let quoteAnnotations: [PostNumber: String]
    /// The quote link to emphasise — set when the user jumped here from that post.
    public let highlightedQuote: PostNumber?

    public init(
        theme: ChanTheme,
        fontSize: CGFloat,
        revealedSpoilers: Set<Int> = [],
        quoteAnnotations: [PostNumber: String] = [:],
        highlightedQuote: PostNumber? = nil
    ) {
        self.theme = theme
        self.fontSize = fontSize
        self.revealedSpoilers = revealedSpoilers
        self.quoteAnnotations = quoteAnnotations
        self.highlightedQuote = highlightedQuote
    }

    public var baseFont: UIFont { .systemFont(ofSize: fontSize) }
    public var annotationFont: UIFont { .systemFont(ofSize: max(fontSize - 3, 9), weight: .semibold) }
    public var monospacedFont: UIFont { .monospacedSystemFont(ofSize: max(fontSize - 1, 10), weight: .regular) }

    public func attributedString(for body: PostBody) -> NSAttributedString {
        let output = NSMutableAttributedString()

        for (index, run) in body.runs.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(for: run.style),
                .foregroundColor: color(for: run.style),
            ]

            if run.style.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if run.style.contains(.code) {
                attributes[.backgroundColor] = UIColor(theme.elevated)
            }

            if let link = run.link {
                attributes[.link] = link.url
                switch link {
                case .quote:
                    attributes[.foregroundColor] = UIColor(theme.link)
                case .external:
                    attributes[.foregroundColor] = UIColor(theme.link)
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                case .dead:
                    attributes[.foregroundColor] = UIColor(theme.tertiaryText)
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }

            if case let .quote(number)? = run.link, number == highlightedQuote {
                // The reader came here from this post's reply: mark the link that
                // points back, which is otherwise impossible to spot in a post
                // quoting twenty people.
                attributes[.backgroundColor] = UIColor(theme.accent).withAlphaComponent(0.30)
            }

            if run.style.contains(.spoiler) {
                if revealedSpoilers.contains(index) {
                    attributes[.backgroundColor] = UIColor(theme.elevated)
                } else {
                    attributes[.foregroundColor] = UIColor(theme.spoilerOverlay)
                    attributes[.backgroundColor] = UIColor(theme.spoilerOverlay)
                    attributes[.chanSpoiler] = index
                }
            }

            output.append(NSAttributedString(string: run.text, attributes: attributes))

            if case let .quote(number)? = run.link, let annotation = quoteAnnotations[number] {
                output.append(
                    NSAttributedString(
                        string: " (\(annotation))",
                        attributes: [
                            .font: annotationFont,
                            .foregroundColor: UIColor(theme.accent),
                        ]
                    )
                )
            }
        }

        return output
    }

    private func color(for style: PostStyle) -> UIColor {
        if style.contains(.quote) { return UIColor(theme.quote) }
        return UIColor(theme.primaryText)
    }

    private func font(for style: PostStyle) -> UIFont {
        if style.contains(.code) { return monospacedFont }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if style.contains(.bold) { traits.insert(.traitBold) }
        if style.contains(.italic) { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return baseFont }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
        return UIFont(descriptor: descriptor, size: fontSize)
    }
}
