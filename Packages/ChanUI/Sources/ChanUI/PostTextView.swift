import ChanCore
import SwiftUI
import UIKit

/// A non-scrolling text view that renders a `PostBody`.
///
/// It owns link routing (quote links, external links) and spoiler reveal, which
/// SwiftUI's `Text` cannot express per-run on iOS 15. All hit-testing uses
/// `UITextInput.characterRange(at:)`, so it works with both TextKit 1 and 2.
public final class PostTextView: UITextView {
    /// Called when a `>>123` link is tapped.
    public var onQuoteTap: ((PostNumber) -> Void)?
    /// Called when a regular link is tapped.
    public var onLinkTap: ((URL) -> Void)?
    /// Called when a spoiler is revealed.
    public var onSpoilerReveal: (() -> Void)?

    private var body: PostBody?
    private var revealedSpoilers: Set<Int> = []
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
    }

    public func configure(body: PostBody, theme: ChanTheme, fontSize: CGFloat, revealedSpoilers: Set<Int> = []) {
        self.body = body
        self.theme = theme
        self.fontSize = fontSize
        self.revealedSpoilers = revealedSpoilers
        render()
    }

    private func render() {
        guard let body else {
            attributedText = nil
            return
        }
        let renderer = PostBodyRenderer(theme: theme, fontSize: fontSize, revealedSpoilers: revealedSpoilers)
        attributedText = renderer.attributedString(for: body)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard let textRange = characterRange(at: point) else { return }
        let index = offset(from: beginningOfDocument, to: textRange.start)
        guard index >= 0, index < attributedText.length else { return }

        if let url = attributedText.attribute(.link, at: index, effectiveRange: nil) as? URL {
            route(url)
            return
        }

        var range = NSRange()
        if let spoilerIndex = attributedText.attribute(.chanSpoiler, at: index, effectiveRange: &range) as? Int {
            revealedSpoilers.insert(spoilerIndex)
            render()
            onSpoilerReveal?()
        }
    }

    private func route(_ url: URL) {
        if let link = PostLink.from(url: url) {
            switch link {
            case let .quote(number):
                onQuoteTap?(number)
            case let .dead(number):
                onQuoteTap?(number)
            case .external:
                break
            }
            return
        }
        onLinkTap?(url)
    }
}
