import AVKit
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
    let searchTerm: String?
    @Binding var pendingScroll: PostNumber?
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
        controller.applySearch(term: searchTerm)

        if let target = pendingScroll {
            controller.scrollToPost(target)
            // Deferred: never mutate SwiftUI state during an update pass.
            DispatchQueue.main.async { pendingScroll = nil }
        }
    }
}

// MARK: - Catalog

public struct CatalogScreen: View {
    @StateObject private var store: CatalogStore
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.chanTheme) private var theme
    @State private var selected: Post?
    @State private var showComposer = false
    @State private var query = ""

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
        .searchable(text: $query, prompt: "Search threads")
        .onChange(of: query) { store.setQuery($0) }
        .background(theme.background.ignoresSafeArea())
        .background(threadLink)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        ForEach(CatalogSort.allCases) { sort in
                            Button {
                                settings.catalogSort = sort
                                ChanHaptics.selection()
                            } label: {
                                if settings.catalogSort == sort {
                                    Label(sort.label, systemImage: "checkmark")
                                } else {
                                    Label(sort.label, systemImage: sort.systemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    Button {
                        settings.toggleFavorite(store.board)
                        ChanHaptics.tap()
                    } label: {
                        Image(systemName: settings.isFavorite(store.board) ? "star.fill" : "star")
                    }
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .tint(theme.accent)
            }
        }
        .onChange(of: settings.catalogSort) { sort in
            store.setSort(sort)
        }
        .sheet(isPresented: $showComposer) {
            ComposerScreen(board: store.board, thread: nil)
                .environment(\.chanTheme, theme)
        }
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
        if store.threads.isEmpty, store.isLoading, !store.isFiltering {
            ProgressView().tint(theme.accent)
        } else if store.threads.isEmpty, store.isFiltering {
            VStack(spacing: ChanSpacing.s) {
                Text("No threads match \"\(store.query)\"")
                    .font(.subheadline)
                    .foregroundColor(theme.secondaryText)
                Text("Searching the threads already loaded, across subjects, post text and filenames.")
                    .font(.caption2)
                    .foregroundColor(theme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(ChanSpacing.xl)
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
    @StateObject private var summaryStore: ThreadSummaryStore
    @StateObject private var chatStore: ThreadChatStore
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.chanTheme) private var theme
    @State private var mediaPost: Post?
    @State private var showComposer = false
    @State private var showSummary = false
    @State private var findQuery = ""
    @State private var matches: [PostNumber] = []
    @State private var matchIndex = 0
    @State private var pendingScroll: PostNumber?

    public init(board: BoardID, op: PostNumber) {
        _store = StateObject(wrappedValue: ThreadStore(board: board, op: op, environment: .shared))
        _summaryStore = StateObject(
            wrappedValue: ThreadSummaryStore(board: board, op: op, environment: .shared)
        )
        _chatStore = StateObject(
            wrappedValue: ThreadChatStore(board: board, op: op, environment: .shared)
        )
    }

    /// Moves through the find matches, wrapping at either end.
    private func step(by delta: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + matches.count) % matches.count
        pendingScroll = matches[matchIndex]
        ChanHaptics.selection()
    }

    public var body: some View {
        ThreadCollectionView(
            store: store,
            theme: theme,
            fontSize: settings.fontSize,
            searchTerm: findQuery.isEmpty ? nil : findQuery,
            pendingScroll: $pendingScroll,
            onOpenMedia: { mediaPost = $0 }
        )
        .navigationTitle("#\(store.op.value)")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $findQuery, prompt: "Find in thread")
        .onChange(of: findQuery) { query in
            matches = store.search(query)
            matchIndex = 0
            pendingScroll = matches.first
        }
        .background(theme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // While a find is active the toolbar becomes its controls;
                    // there is no room for both, and find is the active task.
                    if !findQuery.isEmpty {
                        Text("\(matchIndex + 1)/\(matches.count)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.secondaryText)
                        Button { step(by: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(matches.isEmpty)
                        Button { step(by: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(matches.isEmpty)
                    } else {
                    Button {
                        showSummary = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    Button {
                        store.toggleWatch()
                        ChanHaptics.tap()
                    } label: {
                        Image(systemName: store.isWatched ? "eye.fill" : "eye")
                    }
                    Button {
                        store.toggleBookmark()
                        ChanHaptics.tap()
                    } label: {
                        Image(systemName: store.isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                    }
                }
                .tint(theme.accent)
            }
        }
        .sheet(isPresented: $showComposer) {
            ComposerScreen(board: store.board, thread: store.op)
                .environment(\.chanTheme, theme)
        }
        .sheet(isPresented: $showSummary, onDismiss: {
            summaryStore.cancel()
            chatStore.cancel()
        }) {
            ThreadSummaryScreen(store: summaryStore, chat: chatStore, posts: store.posts)
                .environment(\.chanTheme, theme)
        }
        .task {
            await store.loadIfNeeded()
            store.refreshUserState()

            // Live thread: poll the tail endpoint while the screen is visible.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                await store.pollForNewPosts()
            }
        }
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
                    videoView(attachment)
                } else if attachment.isAnimated {
                    ChanGIFImage(url: ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext))
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

    @ViewBuilder
    private func videoView(_ attachment: Attachment) -> some View {
        let url = ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext)
        if attachment.ext.lowercased().contains("mp4") {
            NativeVideoPlayer(url: url)
        } else {
            VLCVideoView(url: url)
        }
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
        imageView.scaling = .fit
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

/// Native playback for `.mp4` attachments (AVFoundation cannot decode webm).
struct NativeVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            guard player == nil else { return }
            let newPlayer = AVPlayer(url: url)
            newPlayer.isMuted = true
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
