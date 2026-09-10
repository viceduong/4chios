import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import Combine
import SwiftUI
import UIKit

/// The thread timeline: one self-sizing cell per post, with quote navigation.
public final class ThreadViewController: UIViewController {
    private enum Section { case main }

    private let store: ThreadStore
    private let onOpenMedia: (Post) -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, PostNumber>!
    private var postsByNumber: [PostNumber: Post] = [:]

    private var theme: ChanTheme
    private var fontSize: CGFloat
    private var cancellables = Set<AnyCancellable>()

    public init(
        store: ThreadStore,
        theme: ChanTheme,
        fontSize: CGFloat,
        onOpenMedia: @escaping (Post) -> Void
    ) {
        self.store = store
        self.theme = theme
        self.fontSize = fontSize
        self.onOpenMedia = onOpenMedia
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(theme.background)
        configureCollectionView()
        configureDataSource()

        store.$posts
            .receive(on: RunLoop.main)
            .sink { [weak self] posts in self?.apply(posts) }
            .store(in: &cancellables)
    }

    public func applyTheme(_ theme: ChanTheme, fontSize: CGFloat) {
        self.theme = theme
        self.fontSize = fontSize
        view.backgroundColor = UIColor(theme.background)
        collectionView.reloadData()
    }

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear

        let layout = UICollectionViewCompositionalLayout.list(using: configuration)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delegate = self
        collectionView.register(PostCell.self, forCellWithReuseIdentifier: PostCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(theme.accent)
        refresh.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        collectionView.refreshControl = refresh

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, PostNumber>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, number in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PostCell.reuseIdentifier, for: indexPath)
            guard let self, let post = self.postsByNumber[number], let postCell = cell as? PostCell else {
                return cell
            }

            postCell.configure(
                post: post,
                board: self.store.board,
                theme: self.theme,
                fontSize: self.fontSize
            )
            postCell.onQuoteTap = { [weak self] quoted in self?.scrollTo(quoted) }
            postCell.onLinkTap = { url in UIApplication.shared.open(url) }
            postCell.onMediaTap = { [weak self] in
                guard let self, let current = self.postsByNumber[number] else { return }
                self.onOpenMedia(current)
            }
            return postCell
        }
    }

    private func apply(_ posts: [Post]) {
        postsByNumber = Dictionary(uniqueKeysWithValues: posts.map { ($0.no, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, PostNumber>()
        snapshot.appendSections([.main])
        snapshot.appendItems(posts.map(\.no), toSection: .main)

        let shouldAnimate = !posts.isEmpty && collectionView.window != nil
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate)
    }

    private func scrollTo(_ number: PostNumber) {
        guard let indexPath = dataSource.indexPath(for: number) else { return }
        ChanHaptics.softTap()
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            (self?.collectionView.cellForItem(at: indexPath) as? PostCell)?.flash()
        }
    }

    @objc private func refreshPulled() {
        Task {
            await store.refresh()
            collectionView.refreshControl?.endRefreshing()
        }
    }
}

extension ThreadViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let number = dataSource.itemIdentifier(for: indexPath) else { return }
        try? store.markRead(upTo: number)
    }
}

/// One post. OP posts render a subject, statistics and a larger header.
final class PostCell: UICollectionViewCell {
    static let reuseIdentifier = "PostCell"

    var onQuoteTap: ((PostNumber) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onMediaTap: (() -> Void)?

    private let container = UIView()
    private let headerLabel = UILabel()
    private let subjectLabel = UILabel()
    private let bodyTextView = PostTextView()
    private let mediaView = MediaThumbnailView()
    private let footerLabel = UILabel()
    private let opTag = ChanTagLabel()

    private var mediaZeroHeightConstraint: NSLayoutConstraint!
    private var mediaMinHeightConstraint: NSLayoutConstraint!
    private var mediaMaxHeightConstraint: NSLayoutConstraint!
    private var mediaAspectConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        container.layer.cornerRadius = ChanRadius.medium
        container.layer.cornerCurve = .continuous
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        headerLabel.numberOfLines = 1
        subjectLabel.numberOfLines = 0
        footerLabel.numberOfLines = 1
        footerLabel.font = .systemFont(ofSize: 11)

        opTag.text = "OP"
        opTag.isHidden = true

        bodyTextView.onQuoteTap = { [weak self] number in self?.onQuoteTap?(number) }
        bodyTextView.onLinkTap = { [weak self] url in self?.onLinkTap?(url) }
        mediaView.onTap = { [weak self] in self?.onMediaTap?() }

        let headerRow = UIStackView(arrangedSubviews: [opTag, headerLabel])
        headerRow.axis = .horizontal
        headerRow.spacing = 6
        headerRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [headerRow, subjectLabel, bodyTextView, mediaView, footerLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(2, after: headerRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        mediaZeroHeightConstraint = mediaView.heightAnchor.constraint(equalToConstant: 0)
        mediaMinHeightConstraint = mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        mediaMaxHeightConstraint = mediaView.heightAnchor.constraint(lessThanOrEqualToConstant: 340)
        mediaZeroHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        mediaView.reset()
        mediaAspectConstraint?.isActive = false
        mediaAspectConstraint = nil
        bodyTextView.configure(body: PostBody(runs: []), theme: .dark, fontSize: 15)
        onQuoteTap = nil
        onLinkTap = nil
        onMediaTap = nil
    }

    func configure(post: Post, board: BoardID, theme: ChanTheme, fontSize: CGFloat) {
        container.backgroundColor = UIColor(theme.surface)
        headerLabel.attributedText = header(for: post, theme: theme)
        subjectLabel.attributedText = subject(for: post, theme: theme)
        subjectLabel.isHidden = subjectLabel.attributedText?.length == 0

        opTag.backgroundColor = UIColor(theme.accent)
        opTag.isHidden = !post.isOP

        let body = PostHTMLParser.parse(post.commentHTML ?? "")
        bodyTextView.configure(body: body, theme: theme, fontSize: fontSize)

        // Size the media box to the attachment's real aspect ratio, clamped to a
        // sane range. The box matches the image exactly, so `.fit` never
        // letterboxes in the common case and never distorts in any case.
        mediaAspectConstraint?.isActive = false
        mediaAspectConstraint = nil

        if let attachment = post.attachment {
            mediaZeroHeightConstraint.isActive = false
            mediaMinHeightConstraint.isActive = true
            mediaMaxHeightConstraint.isActive = true

            let ratio = attachment.aspectRatio > 0 ? attachment.aspectRatio : 1
            let aspect = mediaView.heightAnchor.constraint(
                equalTo: mediaView.widthAnchor,
                multiplier: 1 / ratio
            )
            aspect.priority = .defaultHigh
            aspect.isActive = true
            mediaAspectConstraint = aspect

            mediaView.isHidden = false
            mediaView.configure(attachment: attachment, board: board, theme: theme)
        } else {
            mediaMinHeightConstraint.isActive = false
            mediaMaxHeightConstraint.isActive = false
            mediaZeroHeightConstraint.isActive = true
            mediaView.isHidden = true
            mediaView.reset()
        }

        if post.isOP, let replies = post.replies, let images = post.images {
            footerLabel.text = "Replies: \(replies)  ·  Images: \(images)"
            footerLabel.isHidden = false
        } else {
            footerLabel.text = nil
            footerLabel.isHidden = true
        }
        footerLabel.textColor = UIColor(theme.tertiaryText)
    }

    func flash() {
        let original = container.backgroundColor
        UIView.animate(withDuration: 0.15) {
            self.container.backgroundColor = self.container.backgroundColor?.withAlphaComponent(0.4)
        } completion: { _ in
            UIView.animate(withDuration: 0.45) {
                self.container.backgroundColor = original
            }
        }
    }

    private func header(for post: Post, theme: ChanTheme) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let nameFont = UIFont.systemFont(ofSize: 12, weight: .semibold)

        let name = post.name ?? "Anonymous"
        output.append(NSAttributedString(
            string: name,
            attributes: [.font: nameFont, .foregroundColor: UIColor(theme.primaryText)]
        ))

        if let trip = post.trip {
            output.append(NSAttributedString(
                string: " \(trip)",
                attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor(theme.accent)]
            ))
        }
        if let capcode = post.capcode {
            output.append(NSAttributedString(
                string: " ## \(capcode)",
                attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: UIColor(theme.danger)]
            ))
        }
        if let country = post.country, let countryName = post.countryName {
            output.append(NSAttributedString(
                string: " \(countryName) [\(country)]",
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor(theme.secondaryText)]
            ))
        }

        let date = ChanFormat.postDate(post.time)
        output.append(NSAttributedString(
            string: "  \(date)",
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: UIColor(theme.tertiaryText)]
        ))

        if let posterID = post.posterID {
            output.append(NSAttributedString(
                string: "  ID:\(posterID)",
                attributes: [.font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: UIColor(theme.tertiaryText)]
            ))
        }

        return output
    }

    private func subject(for post: Post, theme: ChanTheme) -> NSAttributedString {
        guard let subject = post.subject, !subject.isEmpty else { return NSAttributedString() }
        return NSAttributedString(
            string: subject,
            attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor(theme.primaryText)]
        )
    }
}

/// Thumbnail with a format badge and spoiler treatment.
final class MediaThumbnailView: UIView {
    private let imageView = ChanImageView()
    private let badge = ChanTagLabel()
    private let spoilerLabel = UILabel()
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        clipsToBounds = true
        layer.cornerRadius = ChanRadius.small
        layer.cornerCurve = .continuous

        imageView.scaling = .fit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        spoilerLabel.text = "SPOILER"
        spoilerLabel.font = .systemFont(ofSize: 12, weight: .heavy)
        spoilerLabel.textColor = .white
        spoilerLabel.translatesAutoresizingMaskIntoConstraints = false
        spoilerLabel.isHidden = true
        addSubview(spoilerLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            spoilerLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            spoilerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    func reset() {
        imageView.reset()
        badge.isHidden = true
        spoilerLabel.isHidden = true
    }

    func configure(attachment: Attachment, board: BoardID, theme: ChanTheme) {
        backgroundColor = UIColor(theme.elevated)
        badge.backgroundColor = UIColor(theme.primaryText).withAlphaComponent(0.75)
        badge.textColor = .white

        if attachment.isSpoiler {
            imageView.load(ChanMediaURL.spoilerImage(board: board))
            imageView.alpha = 0.5
            spoilerLabel.isHidden = false
        } else {
            imageView.load(ChanMediaURL.thumbnail(board: board, tim: attachment.tim))
            imageView.alpha = 1
            spoilerLabel.isHidden = true
        }

        if attachment.isVideo {
            let ext = attachment.ext.uppercased().replacingOccurrences(of: ".", with: "")
            badge.text = ext.isEmpty ? "VIDEO" : ext
            badge.isHidden = false
        } else if attachment.isAnimated {
            badge.text = "GIF"
            badge.isHidden = false
        } else {
            badge.text = ChanFormat.bytes(attachment.size)
            badge.isHidden = false
        }
    }

    @objc private func handleTap() {
        ChanHaptics.tap()
        onTap?()
    }
}
