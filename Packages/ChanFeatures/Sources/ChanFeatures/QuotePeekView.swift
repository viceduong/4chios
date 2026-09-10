import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import UIKit

/// The long-press quote preview: a peek at the referenced post without leaving
/// the reader's place in the thread.
///
/// 4chan-X shows this on hover; on a phone the equivalent is a bottom card that
/// can be dismissed or turned into a jump.
final class QuotePeekView: UIView {
    private let card = UIView()
    private let headerLabel = UILabel()
    private let bodyTextView = PostTextView()
    private let thumbnail = ChanImageView()
    private let jumpButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private var onJump: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        alpha = 0
        isHidden = true

        card.layer.cornerRadius = ChanRadius.large
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.22
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        headerLabel.numberOfLines = 1
        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        bodyTextView.isUserInteractionEnabled = false

        thumbnail.scaling = .fit
        thumbnail.cornerRadius = ChanRadius.small
        thumbnail.translatesAutoresizingMaskIntoConstraints = false

        jumpButton.setTitle("Jump to post", for: .normal)
        jumpButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        jumpButton.addTarget(self, action: #selector(handleJump), for: .touchUpInside)

        closeButton.setTitle("✕", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        closeButton.addTarget(self, action: #selector(dismiss), for: .touchUpInside)

        let footer = UIStackView(arrangedSubviews: [jumpButton, UIView(), closeButton])
        footer.axis = .horizontal
        footer.alignment = .center

        let stack = UIStackView(arrangedSubviews: [headerLabel, bodyTextView, thumbnail, footer])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),

            thumbnail.heightAnchor.constraint(lessThanOrEqualToConstant: 140),
        ])
    }

    func show(
        post: Post,
        board: BoardID,
        theme: ChanTheme,
        fontSize: CGFloat,
        replyCount: Int,
        isMine: Bool,
        in host: UIView,
        onJump: @escaping () -> Void
    ) {
        self.onJump = onJump

        card.backgroundColor = UIColor(theme.elevated)
        headerLabel.textColor = UIColor(theme.secondaryText)
        jumpButton.tintColor = UIColor(theme.accent)
        closeButton.tintColor = UIColor(theme.tertiaryText)

        var parts = [">>\(post.no.value)"]
        if post.isOP { parts.append("OP") }
        if isMine { parts.append("you") }
        parts.append(post.name ?? "Anonymous")
        if replyCount > 0 {
            parts.append("\(replyCount) \(replyCount == 1 ? "reply" : "replies")")
        }
        headerLabel.text = parts.joined(separator: "  ·  ")

        let body = PostHTMLParser.parse(post.commentHTML ?? "")
        if body.isEmpty {
            // A post that is only a file still deserves its peek.
            bodyTextView.isHidden = true
        } else {
            bodyTextView.isHidden = false
            bodyTextView.configure(body: body, theme: theme, fontSize: fontSize)
        }

        if let attachment = post.attachment, !attachment.isVideo {
            thumbnail.isHidden = false
            thumbnail.load(ChanMediaURL.thumbnail(board: board, tim: attachment.tim))
        } else {
            thumbnail.isHidden = true
            thumbnail.reset()
        }

        isHidden = false
        transform = CGAffineTransform(translationX: 0, y: 24)
        UIView.animate(withDuration: ChanMotion.standard, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    @objc func dismiss() {
        guard !isHidden else { return }
        UIView.animate(withDuration: ChanMotion.quick) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: 16)
        } completion: { _ in
            self.isHidden = true
            self.transform = .identity
            self.thumbnail.reset()
        }
    }

    @objc private func handleJump() {
        onJump?()
    }
}
