import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import Combine
import SwiftUI
import UIKit

/// The board catalog as a two-column card grid.
public final class CatalogViewController: UIViewController {
    private enum Section { case main }

    private let store: CatalogStore
    private let onSelect: (Post) -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, PostNumber>!
    private var postsByNumber: [PostNumber: Post] = [:]

    private var theme: ChanTheme
    private var showThumbnails: Bool

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

    public func applyTheme(_ theme: ChanTheme, showThumbnails: Bool) {
        self.theme = theme
        self.showThumbnails = showThumbnails
        view.backgroundColor = UIColor(theme.background)
        collectionView.reloadData()
    }

    private var cancellables = Set<AnyCancellable>()

    private func configureCollectionView() {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .fractionalHeight(1)
            )
        )
        item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(226)),
            subitems: [item]
        )

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 32, trailing: 8)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
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
        dataSource.apply(snapshot, animatingDifferences: posts.count != postsByNumber.count ? false : true)
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
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(thumbnail)

        subjectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        subjectLabel.numberOfLines = 2

        statsLabel.font = .systemFont(ofSize: 11, weight: .regular)

        stickyTag.text = "STICKY"
        stickyTag.isHidden = true
        stickyTag.translatesAutoresizingMaskIntoConstraints = false

        let labels = UIStackView(arrangedSubviews: [subjectLabel, statsLabel])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels)
        card.addSubview(stickyTag)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnail.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            thumbnail.topAnchor.constraint(equalTo: card.topAnchor),
            thumbnail.heightAnchor.constraint(equalToConstant: 128),

            labels.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            labels.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            labels.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 6),
            labels.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6),

            stickyTag.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            stickyTag.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.reset()
    }

    func configure(post: Post, board: BoardID, theme: ChanTheme, showThumbnail: Bool) {
        card.backgroundColor = UIColor(theme.surface)
        // Show the whole thumbnail, undistorted. The box is a fixed size, so a
        // non-matching aspect ratio letterboxes against the card background
        // instead of being cropped or stretched.
        thumbnail.scaling = .fit
        thumbnail.placeholderColor = UIColor(theme.elevated)
        subjectLabel.textColor = UIColor(theme.primaryText)
        statsLabel.textColor = UIColor(theme.secondaryText)
        stickyTag.backgroundColor = UIColor(theme.accent)
        stickyTag.isHidden = !(post.isSticky ?? false)

        let subject = post.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        subjectLabel.text = (subject?.isEmpty == false ? subject : nil) ?? "No subject"

        let replies = post.replies ?? 0
        let images = post.images ?? 0
        statsLabel.text = "R: \(ChanFormat.count(replies))  I: \(ChanFormat.count(images))"

        if showThumbnail, let attachment = post.attachment {
            let url = attachment.isSpoiler
                ? ChanMediaURL.spoilerImage(board: board)
                : ChanMediaURL.thumbnail(board: board, tim: attachment.tim)
            thumbnail.load(url)
            thumbnail.alpha = attachment.isSpoiler ? 0.55 : 1
        } else {
            thumbnail.reset()
            thumbnail.alpha = 1
        }
    }
}
