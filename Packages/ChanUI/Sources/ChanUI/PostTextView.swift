import ChanCore
import SwiftUI
import UIKit

/// A non-scrolling text view that renders a `PostBody`.
///
/// It owns link routing (quote links, external links), spoiler reveal and
/// long-press quote previews, which SwiftUI's `Text` cannot express per-run on
/// iOS 15. All hit-testing uses `UITextInput.characterRange(at:)`, so it works
/// with both TextKit 1 and 2.
public final class PostTextView: UITextView {
    /// Called when a `>>123` link is tapped.
    public var onQuoteTap: ((PostNumber) -> Void)?
    /// Called when a `>>123` link is long-pressed: show the quoted post.
    public var onQuoteLongPress: ((PostNumber) -> Void)?
    /// Called when a regular link is tapped.
    public var onLinkTap: ((URL) -> Void)?
    /// Called when a spoiler is revealed.
    public var onSpoilerReveal: (() -> Void)?

    private var body: PostBody?
    private var revealedSpoilers: Set<Int> = []
    private var quoteAnnotations: [PostNumber: String] = [:]
    private var highlightedQuote: PostNumber?
    private var searchTerm: String?
    private var theme: ChanTheme = .dark
    private var fontSize: CGFloat = 15

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        configureView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    private func configureView() {
        isEditable = false
        isSelectable = false
        isScrollEnabled = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        dataDetectorTypes = []
        adjustsFontForContentSizeCategory = true
        setContentCompressionResistancePriority(.required, for: .vertical)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        addGestureRecognizer(longPress)
    }

    public func configure(
        body: PostBody,
        theme: ChanTheme,
        fontSize: CGFloat,
        revealedSpoilers: Set<Int> = [],
        quoteAnnotations: [PostNumber: String] = [:],
        highlightedQuote: PostNumber? = nil,
        searchTerm: String? = nil
    ) {
        self.body = body
        self.theme = theme
        self.fontSize = fontSize
        self.revealedSpoilers = revealedSpoilers
        self.quoteAnnotations = quoteAnnotations
        self.highlightedQuote = highlightedQuote
        self.searchTerm = searchTerm
        render()
    }

    private func render() {
        guard let body else {
            attributedText = nil
            return
        }
        let renderer = PostBodyRenderer(
            theme: theme,
            fontSize: fontSize,
            revealedSpoilers: revealedSpoilers,
            quoteAnnotations: quoteAnnotations,
            highlightedQuote: highlightedQuote,
            searchTerm: searchTerm
        )
        attributedText = renderer.attributedString(for: body)
    }

    // MARK: - Hit testing

    /// The link under a point, if any.
    private func link(at point: CGPoint) -> URL? {
        guard let textRange = characterRange(at: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: textRange.start)
        guard index >= 0, index < attributedText.length else { return nil }
        return attributedText.attribute(.link, at: index, effectiveRange: nil) as? URL
    }

    private func spoilerIndex(at point: CGPoint) -> Int? {
        guard let textRange = characterRange(at: point) else { return nil }
        let index = offset(from: beginningOfDocument, to: textRange.start)
        guard index >= 0, index < attributedText.length else { return nil }
        return attributedText.attribute(.chanSpoiler, at: index, effectiveRange: nil) as? Int
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)

        if let url = link(at: point) {
            route(url)
            return
        }

        if let spoiler = spoilerIndex(at: point) {
            revealedSpoilers.insert(spoiler)
            render()
            onSpoilerReveal?()
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let url = link(at: gesture.location(in: self)) else { return }
        guard case let .quote(number)? = PostLink.from(url: url) else { return }
        ChanHaptics.softTap()
        onQuoteLongPress?(number)
    }

    private func route(_ url: URL) {
        if let link = PostLink.from(url: url) {
            switch link {
            case let .quote(number), let .dead(number):
                onQuoteTap?(number)
            case .external:
                break
            }
            return
        }
        onLinkTap?(url)
    }
}
