import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import SwiftUI
import UIKit

// MARK: - UIKit bridges

struct CatalogCollectionView: UIViewControllerRepresentable {
    @ObservedObject var store: CatalogStore
    let theme: ChanTheme
    let showThumbnails: Bool
    let onSelect: (Post) -> Void

    func makeUIViewController(context: Context) -> CatalogViewController {
        CatalogViewController(
            store: store,
            theme: theme,
            showThumbnails: showThumbnails,
            onSelect: onSelect
        )
    }

    func updateUIViewController(_ controller: CatalogViewController, context: Context) {
        controller.applyTheme(theme, showThumbnails: showThumbnails)
    }
}

struct ThreadCollectionView: UIViewControllerRepresentable {
    @ObservedObject var store: ThreadStore
    let theme: ChanTheme
    let fontSize: CGFloat
    let onOpenMedia: (Post) -> Void

    func makeUIViewController(context: Context) -> ThreadViewController {
        ThreadViewController(
            store: store,
            theme: theme,
            fontSize: fontSize,
            onOpenMedia: onOpenMedia
        )
    }

    func updateUIViewController(_ controller: ThreadViewController, context: Context) {
        controller.applyTheme(theme, fontSize: fontSize)
    }
}

// MARK: - Catalog

public struct CatalogScreen: View {
    @StateObject private var store: CatalogStore
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.chanTheme) private var theme
    @State private var selected: Post?

    public init(board: BoardID) {
        _store = StateObject(wrappedValue: CatalogStore(board: board, environment: .shared))
    }

    public var body: some View {
        CatalogCollectionView(
            store: store,
            theme: theme,
            showThumbnails: settings.showThumbnails,
            onSelect: { selected = $0 }
        )
        .navigationTitle("/\(store.board.rawValue)/")
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.background.ignoresSafeArea())
        .background(threadLink)
        .task { await store.loadIfNeeded() }
        .overlay(alignment: .center) { emptyState }
    }

    private var threadLink: some View {
        NavigationLink(
            destination: selected.map { ThreadScreen(board: store.board, op: $0.no) },
            isActive: Binding(
                get: { selected != nil },
                set: { if !$0 { selected = nil } }
            ),
            label: { EmptyView() }
        )
        .hidden()
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.threads.isEmpty, store.isLoading {
            ProgressView().tint(theme.accent)
        } else if store.threads.isEmpty, let message = store.errorMessage {
            VStack(spacing: ChanSpacing.s) {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await store.refresh() } }
                    .font(.footnote.weight(.semibold))
                    .tint(theme.accent)
            }
            .padding(ChanSpacing.xl)
        }
    }
}

// MARK: - Thread

public struct ThreadScreen: View {
    @StateObject private var store: ThreadStore
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.chanTheme) private var theme
    @State private var mediaPost: Post?

    public init(board: BoardID, op: PostNumber) {
        _store = StateObject(wrappedValue: ThreadStore(board: board, op: op, environment: .shared))
    }

    public var body: some View {
        ThreadCollectionView(
            store: store,
            theme: theme,
            fontSize: settings.fontSize,
            onOpenMedia: { mediaPost = $0 }
        )
        .navigationTitle("#\(store.op.value)")
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.background.ignoresSafeArea())
        .task { await store.loadIfNeeded() }
        .sheet(item: $mediaPost) { post in
            MediaViewerScreen(board: store.board, post: post)
        }
    }
}

// MARK: - Media viewer

public struct MediaViewerScreen: View {
    public let board: BoardID
    public let post: Post

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(board: BoardID, post: Post) {
        self.board = board
        self.post = post
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let attachment = post.attachment {
                if attachment.isVideo {
                    videoPlaceholder(attachment)
                } else {
                    ZoomableImageView(url: ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(ChanSpacing.l)
        }
        .overlay(alignment: .bottom) { caption }
    }

    private func videoPlaceholder(_ attachment: Attachment) -> some View {
        VStack(spacing: ChanSpacing.m) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.white.opacity(0.7))
            Text(attachment.ext.uppercased().replacingOccurrences(of: ".", with: ""))
                .font(.headline)
                .foregroundColor(.white)
            Text("Native webm playback lands in the next milestone.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
            Link("Open in Safari", destination: ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext))
                .font(.footnote.weight(.semibold))
                .tint(.white)
        }
        .padding(ChanSpacing.xl)
    }

    @ViewBuilder
    private var caption: some View {
        if let attachment = post.attachment {
            VStack(spacing: 2) {
                Text(attachment.filename)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(ChanFormat.bytes(attachment.size))  ·  \(attachment.width)×\(attachment.height)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            .foregroundColor(.white)
            .padding(.horizontal, ChanSpacing.l)
            .padding(.vertical, ChanSpacing.s)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, ChanSpacing.xl)
        }
    }
}

/// Pinch-to-zoom, double-tap-to-zoom image viewer.
struct ZoomableImageView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.delegate = context.coordinator

        let imageView = ChanImageView()
        imageView.cornerRadius = 0
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        context.coordinator.imageView = imageView
        imageView.load(url)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.load(url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: ChanImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale
            scrollView.setZoomScale(zoomed ? scrollView.minimumZoomScale : 2.5, animated: true)
        }
    }
}
