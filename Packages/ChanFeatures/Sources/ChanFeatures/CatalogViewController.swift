import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import Combine
import SwiftUI
import UIKit

/// Layout constants and text measurement for catalog cards.
///
/// The card is a fixed height and the **image takes whatever the text does not
/// use**, so no card ever shows a gap: a thread with a one-line subject gets a
/// taller image instead of empty space, and a two-line subject shortens it.
enum CatalogMetrics {
    /// Total card height with thumbnails shown.
    static let cardHeightWithImages: CGFloat = 206
    /// Total card height when thumbnails are switched off; just text.
    static let cardHeightWithoutImages: CGFloat = 68
    /// The image never collapses, even for a very long subject.
    static let minimumImageHeight: CGFloat = 84

    /// Horizontal inset for the text block.
    static let textPadding: CGFloat = 7
    /// Gap between the image and the subject.
    static let imageLabelSpacing: CGFloat = 6
    static let subjectStatsSpacing: CGFloat = 2
    /// Gap under the statistics line.
    static let bottomPadding: CGFloat = 8

    static let subjectFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let statsFont = UIFont.systemFont(ofSize: 11, weight: .regular)
    static let maximumSubjectLines = 2

    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 8
    static let sectionInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 28, trailing: 8)

    static func cardHeight(showThumbnails: Bool) -> CGFloat {
        showThumbnails ? cardHeightWithImages : cardHeightWithoutImages
    }

    /// The text shown under the thumbnail. Never empty, so the measurement below
    /// always has something to measure.
    static func displaySubject(for post: Post) -> String {
        let subject = post.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let subject, !subject.isEmpty else { return "No subject" }
        return subject
    }

    static func stats(for post: Post) -> String {
        "R: \(ChanFormat.count(post.replies ?? 0))   I: \(ChanFormat.count(post.images ?? 0))"
    }

    /// Height the subject label will actually occupy, capped at two lines.
    static func subjectHeight(of text: String, cardWidth: CGFloat) -> CGFloat {
        let available = max(cardWidth - textPadding * 2, 1)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: available, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: subjectFont],
            context: nil
        )
        // A point of slack stops rounding from clipping the second line.
        let measured = ceil(bounding.height) + 1
        return min(measured, ceil(subjectFont.lineHeight) * CGFloat(maximumSubjectLines))
    }

    /// Everything between the bottom of the image and the bottom of the card:
    /// the gap below the image, the two label lines, and the bottom padding.
    static func textBlockHeight(for post: Post, cardWidth: CGFloat) -> CGFloat {
        imageLabelSpacing
            + subjectHeight(of: displaySubject(for: post), cardWidth: cardWidth)
            + subjectStatsSpacing
            + ceil(statsFont.lineHeight)
            + bottomPadding
    }

    /// The image fills all the space the text does not need, so the label stack
    /// lands exactly on the card's bottom padding and nothing is left over.
    static func imageHeight(for post: Post, cardWidth: CGFloat, showThumbnails: Bool) -> CGFloat {
        guard showThumbnails else { return 0 }
        let available = cardHeight(showThumbnails: true) - textBlockHeight(for: post, cardWidth: cardWidth)
        return max(available, minimumImageHeight)
    }
}

/// The board catalog as a tight two-column card grid.
public final class CatalogViewController: UIViewController {
    private enum Section { case main }

    private let store: CatalogStore
    private let onSelect: (Post) -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, PostNumber>!
    private var postsByNumber: [PostNumber: Post] = [:]

    private var theme: ChanTheme
    private var showThumbnails: Bool
    private var cancellables = Set<AnyCancellable>()
    private var lastViewWidth: CGFloat = 0

    public init(store: CatalogStore, theme: ChanTheme, showThumbnails: Bool, onSelect: @escaping (Post) -> Void) {
        self.store = store
        self.theme = theme
        self.showThumbnails = showThumbnails
        self.onSelect = onSelect
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

        store.$threads
            .receive(on: RunLoop.main)
            .sink { [weak self] posts in self?.apply(posts) }
            .store(in: &cancellables)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Cells recompute their image height from their own width, so a width
        // change needs a reload. Guarded on the width: reloading unconditionally
        // here would retrigger layout forever.
        let width = view.bounds.width
        guard abs(width - lastViewWidth) > 0.5 else { return }
        lastViewWidth = width
        collectionView.reloadData()
    }

    public func applyTheme(_ theme: ChanTheme, showThumbnails: Bool) {
        let thumbnailsChanged = showThumbnails != self.showThumbnails
        self.theme = theme
        self.showThumbnails = showThumbnails
        view.backgroundColor = UIColor(theme.background)

        if thumbnailsChanged {
            collectionView.setCollectionViewLayout(makeLayout(showThumbnails: showThumbnails), animated: false)
        }
        collectionView.reloadData()
    }

    // MARK: - Layout

    private func makeLayout(showThumbnails: Bool) -> UICollectionViewCompositionalLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .fractionalHeight(1)
            )
        )
        item.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: CatalogMetrics.columnSpacing / 2,
            bottom: 0,
            trailing: CatalogMetrics.columnSpacing / 2
        )

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(CatalogMetrics.cardHeight(showThumbnails: showThumbnails))
            ),
            subitems: [item]
        )

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = CatalogMetrics.sectionInsets
        section.interGroupSpacing = CatalogMetrics.rowSpacing
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureCollectionView() {
        collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: makeLayout(showThumbnails: showThumbnails)
        )
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.register(CatalogCell.self, forCellWithReuseIdentifier: CatalogCell.reuseIdentifier)
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
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: CatalogCell.reuseIdentifier, for: indexPath
            )
            guard let self, let post = self.postsByNumber[number], let catalogCell = cell as? CatalogCell else {
                return cell
            }
            catalogCell.configure(post: post, board: self.store.board, theme: self.theme, showThumbnail: self.showThumbnails)
            return catalogCell
        }
    }

    private func apply(_ posts: [Post]) {
        postsByNumber = Dictionary(uniqueKeysWithValues: posts.map { ($0.no, $0) })

        var snapshot = NSDiffableDataSourceSnapshot<Section, PostNumber>()
        snapshot.appendSections([.main])
        snapshot.appendItems(posts.map(\.no), toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: collectionView.window != nil)
    }

    @objc private func refreshPulled() {
        Task {
            await store.refresh()
            collectionView.refreshControl?.endRefreshing()
        }
    }
}

extension CatalogViewController: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let number = dataSource.itemIdentifier(for: indexPath), let post = postsByNumber[number] else { return }
        ChanHaptics.tap()
        onSelect(post)
    }
}

/// One catalog card: thumbnail, subject, and thread statistics.
final class CatalogCell: UICollectionViewCell {
    static let reuseIdentifier = "CatalogCell"

    private let card = UIView()
    private let thumbnail = ChanImageView()
    private let subjectLabel = UILabel()
    private let statsLabel = UILabel()
    private let stickyTag = ChanTagLabel()

    private var imageHeightConstraint: NSLayoutConstraint!
    private var lastLayoutWidth: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        card.layer.cornerRadius = ChanRadius.card
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        thumbnail.cornerRadius = 0
        thumbnail.scaling = .fill
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(thumbnail)

        subjectLabel.font = CatalogMetrics.subjectFont
        subjectLabel.numberOfLines = CatalogMetrics.maximumSubjectLines
        statsLabel.font = CatalogMetrics.statsFont

        stickyTag.text = "STICKY"
        stickyTag.isHidden = true
        stickyTag.translatesAutoresizingMaskIntoConstraints = false

        let labels = UIStackView(arrangedSubviews: [subjectLabel, statsLabel])
        labels.axis = .vertical
        labels.spacing = CatalogMetrics.subjectStatsSpacing
        labels.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels)
        card.addSubview(stickyTag)

        imageHeightConstraint = thumbnail.heightAnchor.constraint(equalToConstant: CatalogMetrics.minimumImageHeight)
        imageHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnail.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            thumbnail.topAnchor.constraint(equalTo: card.topAnchor),

            labels.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: CatalogMetrics.textPadding),
            labels.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -CatalogMetrics.textPadding),
            labels.topAnchor.constraint(
                equalTo: thumbnail.bottomAnchor,
                constant: CatalogMetrics.imageLabelSpacing
            ),

            stickyTag.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            stickyTag.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        guard width > 0, abs(width - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = width
        updateImageHeight(cardWidth: width)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.reset()
        currentPost = nil
        lastLayoutWidth = 0
    }

    private var currentPost: Post?
    private var currentShowThumbnail = true

    func configure(post: Post, board: BoardID, theme: ChanTheme, showThumbnail: Bool) {
        currentPost = post
        currentShowThumbnail = showThumbnail

        card.backgroundColor = UIColor(theme.surface)
        subjectLabel.textColor = UIColor(theme.primaryText)
        statsLabel.textColor = UIColor(theme.secondaryText)
        stickyTag.backgroundColor = UIColor(theme.accent)
        stickyTag.isHidden = !(post.isSticky ?? false)

        subjectLabel.text = CatalogMetrics.displaySubject(for: post)
        statsLabel.text = CatalogMetrics.stats(for: post)

        let width = contentView.bounds.width > 0 ? contentView.bounds.width : lastLayoutWidth
        if width > 0 { updateImageHeight(cardWidth: width) }

        guard showThumbnail, let attachment = post.attachment else {
            thumbnail.reset()
            thumbnail.alpha = 1
            return
        }

        let url = attachment.isSpoiler
            ? ChanMediaURL.spoilerImage(board: board)
            : ChanMediaURL.thumbnail(board: board, tim: attachment.tim)
        thumbnail.load(url)
        thumbnail.alpha = attachment.isSpoiler ? 0.55 : 1
    }

    /// The image takes every point the text does not need, so no card shows a gap.
    private func updateImageHeight(cardWidth: CGFloat) {
        guard let post = currentPost else { return }
        let height = CatalogMetrics.imageHeight(
            for: post,
            cardWidth: cardWidth,
            showThumbnails: currentShowThumbnail
        )
        guard abs(imageHeightConstraint.constant - height) > 0.5 else { return }
        imageHeightConstraint.constant = height
    }
}
