import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import Combine
import SwiftUI
import UIKit

/// The thread timeline: self-sizing post cells with quote backlinks, filter
/// stubs, quote navigation, and long-press previews.
public final class ThreadViewController: UIViewController {
    private enum Section { case main }

    private let store: ThreadStore
    private let onOpenMedia: (Post) -> Void

    /// Actions offered on a long press.
    var onTogglePostBookmark: ((Post) -> Void)?
    var onSaveMedia: ((Post) -> Void)?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, PostNumber>!
    private var postsByNumber: [PostNumber: Post] = [:]

    private var theme: ChanTheme
    private var fontSize: CGFloat
    private var cancellables = Set<AnyCancellable>()

    /// Stubs the user has expanded.
    private var revealedStubs: Set<PostNumber> = []
    /// The find-in-thread term, if any.
    private var searchTerm: String?
    /// Destination post → the post the reader came from, so the single relevant
    /// `>>` link can be highlighted.
    private var highlightTargets: [PostNumber: PostNumber] = [:]

    private let peek = QuotePeekView()

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
        configurePeek()

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

    // MARK: - Setup

    private func configureCollectionView() {
        var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
        configuration.showsSeparators = false
        configuration.backgroundColor = .clear

        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration)
        )
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

            let decision = self.store.filterDecision(for: post)
            let isStub = decision.contains(.stub) && !self.revealedStubs.contains(number)

            postCell.configure(
                post: post,
                board: self.store.board,
                theme: self.theme,
                fontSize: self.fontSize,
                isStub: isStub,
                stubReason: isStub ? self.stubReason(for: post) : nil,
                backlinks: self.store.graph.replies(to: number),
                annotations: self.store.quoteAnnotations(for: post),
                isMine: self.store.myPosts.contains(number),
                quotesYou: self.store.quotesUser(post),
                isHighlighted: decision.contains(.highlight),
                highlightedQuote: self.highlightTargets[number],
                searchTerm: self.searchTerm
            )

            postCell.onQuoteTap = { [weak self] quoted in self?.navigate(to: quoted, from: number) }
            postCell.onQuoteLongPress = { [weak self] quoted in self?.showPeek(for: quoted, from: number) }
            postCell.onBacklinkTap = { [weak self] backlink in self?.navigate(to: backlink, from: number) }
            postCell.onBacklinkLongPress = { [weak self] backlink in self?.showPeek(for: backlink, from: number) }
            postCell.onStubTap = { [weak self] in self?.revealStub(number) }
            postCell.onMediaTap = { [weak self] in
                guard let self, let current = self.postsByNumber[number] else { return }
                self.onOpenMedia(current)
            }
            postCell.onMarkAsMine = { [weak self] in
                self?.store.markAsMine(number)
                ChanHaptics.success()
                self?.reconfigure(number)
            }

            return postCell
        }
    }

    private func configurePeek() {
        peek.translatesAutoresizingMaskIntoConstraints = false
        peek.isHidden = true
        view.addSubview(peek)
        NSLayoutConstraint.activate([
            peek.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            peek.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            peek.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Diffing

    private func apply(_ posts: [Post]) {
        // Hidden posts never reach the list at all.
        let visible = posts.filter { !store.filterDecision(for: $0).contains(.hide) }
        postsByNumber = Dictionary(uniqueKeysWithValues: visible.map { ($0.no, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, PostNumber>()
        snapshot.appendSections([.main])
        snapshot.appendItems(visible.map(\.no), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
    }

    private func reconfigure(_ number: PostNumber) {
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(number) else { return }
        snapshot.reconfigureItems([number])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Interaction

    private func stubReason(for post: Post) -> String {
        let hit = store.filterMatches(for: post).first
        guard let hit else { return "Filtered" }
        return "Filtered by \(hit.filter.match.label.lowercased()) “\(hit.filter.pattern)”"
    }

    private func revealStub(_ number: PostNumber) {
        revealedStubs.insert(number)
        ChanHaptics.selection()
        reconfigure(number)
    }

    /// Scrolls to a post on request from outside, e.g. find-in-thread.
    public func scrollToPost(_ number: PostNumber) {
        navigate(to: number, from: nil)
    }

    /// Marks the current find term in the posts already on screen.
    ///
    /// Only visible cells are reconfigured: reloading a 500-post thread on every
    /// keystroke would be far more work than the highlight is worth.
    public func applySearch(term: String?) {
        let normalized = (term?.isEmpty == true) ? nil : term
        guard normalized != searchTerm else { return }
        searchTerm = normalized
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let number = dataSource.itemIdentifier(for: indexPath) else { continue }
            reconfigure(number)
        }
    }

    /// Jumps to `number`, remembering `source` so the relevant quote link inside
    /// the destination can be highlighted.
    private func navigate(to number: PostNumber, from source: PostNumber?) {
        guard let indexPath = dataSource.indexPath(for: number) else { return }

        if let source {
            highlightTargets[number] = source
            reconfigure(number)
        }

        ChanHaptics.softTap()
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            (self?.collectionView.cellForItem(at: indexPath) as? PostCell)?.flash()
        }

        if source != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                self?.highlightTargets[number] = nil
                self?.reconfigure(number)
            }
        }
    }

    private func showPeek(for number: PostNumber, from source: PostNumber?) {
        guard let post = store.graph.post(number) else { return }
        peek.show(
            post: post,
            board: store.board,
            theme: theme,
            fontSize: fontSize,
            replyCount: store.graph.replyCount(of: number),
            isMine: store.myPosts.contains(number),
            in: view,
            onJump: { [weak self] in
                self?.peek.dismiss()
                self?.navigate(to: number, from: source)
            }
        )
    }

    @objc private func refreshPulled() {
        Task {
            await store.refresh()
            collectionView.refreshControl?.endRefreshing()
        }
    }
}

extension ThreadViewController: UICollectionViewDelegate {
    /// Long press a post for the actions that apply to it alone.
    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let number = dataSource.itemIdentifier(for: indexPath),
              let post = postsByNumber[number] else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            let saved = self.store.bookmarkedPosts.contains(number)
            var actions: [UIMenuElement] = [
                UIAction(
                    title: saved ? "Remove post bookmark" : "Bookmark post",
                    image: UIImage(systemName: saved ? "bookmark.slash" : "bookmark")
                ) { _ in self.onTogglePostBookmark?(post) },
            ]

            if post.attachment != nil {
                actions.append(
                    UIAction(
                        title: "Save media",
                        image: UIImage(systemName: "arrow.down.circle")
                    ) { _ in self.onSaveMedia?(post) }
                )
            }

            actions.append(
                UIAction(title: "Copy text", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = PostHTMLParser.parse(post.commentHTML ?? "").plainText
                }
            )

            return UIMenu(children: actions)
        }
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let number = dataSource.itemIdentifier(for: indexPath) else { return }
        try? store.markRead(upTo: number)
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        peek.dismiss()
    }
}

// MARK: - Post cell

/// One post: header, body, media, backlinks, and an optional filter stub.
final class PostCell: UICollectionViewCell {
    static let reuseIdentifier = "PostCell"

    var onQuoteTap: ((PostNumber) -> Void)?
    var onQuoteLongPress: ((PostNumber) -> Void)?
    var onLinkTap: ((URL) -> Void)?
    var onMediaTap: (() -> Void)?
    var onBacklinkTap: ((PostNumber) -> Void)?
    var onBacklinkLongPress: ((PostNumber) -> Void)?
    var onStubTap: (() -> Void)?
    var onMarkAsMine: (() -> Void)?

    private let container = UIView()
    private let accentBar = UIView()
    private let headerLabel = UILabel()
    private let subjectLabel = UILabel()
    private let bodyTextView = PostTextView()
    private let mediaView = MediaThumbnailView()
    private let backlinkRow = BacklinkRowView()
    private let stubView = StubRowView()
    private let footerLabel = UILabel()
    private let opTag = ChanTagLabel()
    private let ownerTag = ChanTagLabel()
    private let youTag = ChanTagLabel()

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
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)

        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.isHidden = true
        container.addSubview(accentBar)

        headerLabel.numberOfLines = 1
        subjectLabel.numberOfLines = 0
        footerLabel.numberOfLines = 1
        footerLabel.font = .systemFont(ofSize: 11)

        opTag.text = "OP"
        opTag.isHidden = true
        ownerTag.text = "ME"
        ownerTag.isHidden = true
        youTag.text = "(YOU)"
        youTag.isHidden = true

        bodyTextView.onQuoteTap = { [weak self] number in self?.onQuoteTap?(number) }
        bodyTextView.onQuoteLongPress = { [weak self] number in self?.onQuoteLongPress?(number) }
        bodyTextView.onLinkTap = { [weak self] url in self?.onLinkTap?(url) }
        bodyTextView.onSpoilerReveal = { [weak self] in self?.setNeedsLayout() }
        mediaView.onTap = { [weak self] in self?.onMediaTap?() }
        backlinkRow.onTap = { [weak self] number in self?.onBacklinkTap?(number) }
        backlinkRow.onLongPress = { [weak self] number in self?.onBacklinkLongPress?(number) }
        stubView.onTap = { [weak self] in self?.onStubTap?() }

        let tagRow = UIStackView(arrangedSubviews: [opTag, ownerTag, youTag])
        tagRow.axis = .horizontal
        tagRow.spacing = 4
        tagRow.alignment = .center

        let headerRow = UIStackView(arrangedSubviews: [tagRow, headerLabel])
        headerRow.axis = .horizontal
        headerRow.spacing = 6
        headerRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [
            headerRow, subjectLabel, bodyTextView, mediaView, backlinkRow, stubView, footerLabel,
        ])
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

            accentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: container.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 3),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 13),
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
        onQuoteLongPress = nil
        onLinkTap = nil
        onMediaTap = nil
        onBacklinkTap = nil
        onBacklinkLongPress = nil
        onStubTap = nil
        onMarkAsMine = nil
    }

    func configure(
        post: Post,
        board: BoardID,
        theme: ChanTheme,
        fontSize: CGFloat,
        isStub: Bool,
        stubReason: String?,
        backlinks: [PostNumber],
        annotations: [PostNumber: String],
        isMine: Bool,
        quotesYou: Bool,
        isHighlighted: Bool,
        highlightedQuote: PostNumber?,
        searchTerm: String? = nil
    ) {
        container.backgroundColor = isHighlighted
            ? UIColor(theme.accent).withAlphaComponent(0.12)
            : UIColor(theme.surface)

        // The accent bar encodes the post's relationship to the reader, the way
        // 4chan-X's `.quotesYou` and own-post borders do.
        if isMine {
            accentBar.backgroundColor = UIColor(theme.accent)
            accentBar.isHidden = false
        } else if quotesYou {
            accentBar.backgroundColor = UIColor(theme.danger)
            accentBar.isHidden = false
        } else {
            accentBar.isHidden = true
        }

        headerLabel.attributedText = header(for: post, theme: theme)
        opTag.backgroundColor = UIColor(theme.accent)
        opTag.isHidden = !post.isOP
        ownerTag.backgroundColor = UIColor(theme.link)
        ownerTag.isHidden = !isMine
        youTag.backgroundColor = UIColor(theme.danger)
        youTag.isHidden = !quotesYou

        stubView.isHidden = !isStub
        subjectLabel.isHidden = isStub
        bodyTextView.isHidden = isStub
        footerLabel.isHidden = isStub
        backlinkRow.isHidden = isStub || backlinks.isEmpty

        if isStub {
            stubView.configure(reason: stubReason ?? "Filtered", replyCount: backlinks.count, theme: theme)
            mediaAspectConstraint?.isActive = false
            mediaAspectConstraint = nil
            mediaMinHeightConstraint.isActive = false
            mediaMaxHeightConstraint.isActive = false
            mediaZeroHeightConstraint.isActive = true
            mediaView.isHidden = true
            mediaView.reset()
            return
        }

        subjectLabel.attributedText = subject(for: post, theme: theme)
        subjectLabel.isHidden = subjectLabel.attributedText?.length == 0

        let body = PostHTMLParser.parse(post.commentHTML ?? "")
        bodyTextView.configure(
            body: body,
            theme: theme,
            fontSize: fontSize,
            quoteAnnotations: annotations,
            highlightedQuote: highlightedQuote,
            searchTerm: searchTerm
        )

        backlinkRow.configure(backlinks: backlinks, annotations: annotations, theme: theme)

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

        output.append(NSAttributedString(
            string: post.name ?? "Anonymous",
            attributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor(theme.primaryText)]
        ))

        if let trip = post.trip {
            output.append(NSAttributedString(
                string: " \(trip)",
                attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor(theme.accent)]
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

        output.append(NSAttributedString(
            string: "  \(ChanFormat.postDate(post.time))",
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor(theme.tertiaryText),
            ]
        ))

        if let posterID = post.posterID {
            output.append(NSAttributedString(
                string: "  ID:\(posterID)",
                attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: UIColor(theme.tertiaryText),
                ]
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

// MARK: - Backlinks

/// The replies a post received, as tappable `>>N` chips.
final class BacklinkRowView: UIView {
    var onTap: ((PostNumber) -> Void)?
    var onLongPress: ((PostNumber) -> Void)?

    private let glyph = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        glyph.text = "↩"
        glyph.font = .systemFont(ofSize: 11, weight: .bold)
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 5),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 22),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    func configure(backlinks: [PostNumber], annotations: [PostNumber: String], theme: ChanTheme) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        glyph.textColor = UIColor(theme.tertiaryText)

        for number in backlinks {
            let chip = BacklinkChip()
            chip.number = number
            chip.configure(
                text: annotations[number].map { ">>\(number.value) \($0)" } ?? ">>\(number.value)",
                theme: theme,
                emphasized: annotations[number] != nil
            )
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chip.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(chipLongPressed(_:))))
            stack.addArrangedSubview(chip)
        }
    }

    @objc private func chipTapped(_ chip: BacklinkChip) {
        onTap?(chip.number)
    }

    @objc private func chipLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let chip = gesture.view as? BacklinkChip else { return }
        onLongPress?(chip.number)
    }
}

/// A small tappable `>>N` chip.
final class BacklinkChip: UIControl {
    var number: PostNumber = 0
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(text: String, theme: ChanTheme, emphasized: Bool) {
        label.text = text
        label.textColor = emphasized ? UIColor(theme.accent) : UIColor(theme.secondaryText)
        backgroundColor = UIColor(theme.elevated)
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1
        }
    }
}

// MARK: - Stub

/// The collapsed placeholder a `stub` filter action produces.
final class StubRowView: UIControl {
    var onTap: (() -> Void)?

    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        layer.cornerRadius = ChanRadius.small
        layer.cornerCurve = .continuous

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    func configure(reason: String, replyCount: Int, theme: ChanTheme) {
        let replies = replyCount > 0 ? " · \(replyCount) \(replyCount == 1 ? "reply" : "replies")" : ""
        label.text = "\(reason)\(replies)\nTap to show"
        label.font = .systemFont(ofSize: 11)
        label.textColor = UIColor(theme.secondaryText)
        backgroundColor = UIColor(theme.elevated)
    }

    @objc private func handleTap() {
        onTap?()
    }
}

// MARK: - Media

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
