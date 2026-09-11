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
    let onTogglePostBookmark: (Post) -> Void
    let onSaveMedia: (Post) -> Void
    let onOpenMedia: (Post) -> Void

    func makeUIViewController(context: Context) -> ThreadViewController {
        let controller = ThreadViewController(
            store: store,
            theme: theme,
            fontSize: fontSize,
            onOpenMedia: onOpenMedia
        )
        controller.onTogglePostBookmark = onTogglePostBookmark
        controller.onSaveMedia = onSaveMedia
        return controller
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
    @State private var isSearching = false
    @State private var showSummary = false

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
        .safeAreaInset(edge: .top) {
            // Shown only while searching. `.searchable` cannot auto-hide over a
            // bridged UIKit collection view, so its bar stayed pinned over the
            // grid permanently.
            if isSearching {
                ChanSearchBar(
                    placeholder: "Search threads",
                    text: $query,
                    onCancel: {
                        isSearching = false
                        query = ""
                        store.setQuery("")
                    }
                )
            }
        }
        .onChange(of: query) { store.setQuery($0) }
        .background(theme.background.ignoresSafeArea())
        .background(threadLink)
        .sheet(isPresented: $showSummary) {
            CatalogSummaryScreen(board: store.board, threads: store.posts)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        isSearching.toggle()
                        if !isSearching {
                            query = ""
                            store.setQuery("")
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    // Reading the whole board is the catalog's own version of the
                    // thread summary, so it gets a matching icon in the same place.
                    Button {
                        ChanHaptics.tap()
                        showSummary = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
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
    @State private var mode: ThreadMode = .list
    @State private var viewer: ViewerRequest?
    @State private var showComposer = false
    @State private var showSummary = false
    @State private var findQuery = ""
    @State private var matches: [PostNumber] = []
    @State private var matchIndex = 0
    @State private var pendingScroll: PostNumber?
    @State private var isFinding = false
    /// A post to land on once the thread has loaded, e.g. from a saved post.
    private let initialPost: PostNumber?
    @StateObject private var downloader = MediaDownloader()
    @State private var showDownloadOptions = false
    @State private var downloadOptions: [MediaDownloader.Plan] = []

    public init(board: BoardID, op: PostNumber, initialPost: PostNumber? = nil) {
        self.initialPost = initialPost
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

    /// The thread's attachments in reading order, which is both the order the
    /// mosaic shows them in and the order the viewer pages through.
    private var galleryItems: [ThreadGalleryItem] {
        store.posts.compactMap { post in
            post.attachment.map { ThreadGalleryItem(postNumber: post.no, attachment: $0) }
        }
    }

    /// Opening from the list shows that one file. Paging into other posts'
    /// attachments from there would be a surprise, so the pager is reserved for
    /// the gallery, where the whole set is visible and the context is obvious.
    private func openInViewer(_ post: Post) {
        guard let attachment = post.attachment else { return }
        viewer = ViewerRequest(
            items: [ThreadGalleryItem(postNumber: post.no, attachment: attachment)],
            index: 0
        )
    }

    public var body: some View {
        ZStack {
            // Left in the hierarchy while the mosaic is showing, so switching
            // back does not throw away the reader's place in the thread.
            ThreadCollectionView(
            store: store,
            theme: theme,
            fontSize: settings.fontSize,
            searchTerm: findQuery.isEmpty ? nil : findQuery,
            pendingScroll: $pendingScroll,
            onTogglePostBookmark: { post in
                let saved = store.isPostBookmarked(post.no)
                store.setPostBookmarked(post, !saved)
                if saved { ChanHaptics.warning() } else { ChanHaptics.success() }
            },
            onSaveMedia: { post in
                Task {
                    let saved = await downloader.saveSingle(
                        board: store.board,
                        post: post,
                        threadNumber: store.op,
                        environment: .shared
                    )
                    if saved { ChanHaptics.success() } else { ChanHaptics.error() }
                }
            },
            onOpenMedia: { openInViewer($0) }
        )
            .opacity(mode == .list ? 1 : 0)
            .allowsHitTesting(mode == .list)

            if mode == .gallery {
                ThreadGalleryView(
                    board: store.board,
                    items: galleryItems,
                    onOpen: { index in
                        viewer = ViewerRequest(items: galleryItems, index: index)
                    }
                )
            }
        }
        .navigationTitle("#\(store.op.value)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if isFinding {
                ChanSearchBar(
                    placeholder: "Find in thread",
                    text: $findQuery,
                    onCancel: {
                        isFinding = false
                        findQuery = ""
                        matches = []
                    }
                )
            }
        }
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
                    if isFinding {
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
                    if mode == .list {
                        Button {
                            isFinding = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    // Switching view mode is a browsing action, so it keeps a
                    // slot; summarising is an occasional task and moves into the
                    // menu to make room.
                    Button {
                        mode = mode == .list ? .gallery : .list
                        ChanHaptics.tap()
                    } label: {
                        Image(systemName: mode == .gallery ? "list.bullet" : "square.grid.2x2")
                    }
                    Menu {
                        Button {
                            showSummary = true
                        } label: {
                            Label("Summarise thread", systemImage: "sparkles")
                        }
                        Button {
                            store.toggleWatch()
                            ChanHaptics.tap()
                        } label: {
                            Label(
                                store.isWatched ? "Stop watching" : "Watch thread",
                                systemImage: store.isWatched ? "eye.slash" : "eye"
                            )
                        }
                        Button {
                            store.toggleBookmark()
                            ChanHaptics.tap()
                        } label: {
                            Label(
                                store.isBookmarked ? "Remove thread bookmark" : "Bookmark thread",
                                systemImage: store.isBookmarked ? "bookmark.slash" : "bookmark"
                            )
                        }
                        Button {
                            showComposer = true
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                        Button {
                            downloadOptions = downloader.plans(
                                board: store.board,
                                posts: store.posts,
                                environment: .shared
                            )
                            showDownloadOptions = true
                        } label: {
                            Label("Download media", systemImage: "arrow.down.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .confirmationDialog(
            "Download media for offline viewing",
            isPresented: $showDownloadOptions,
            titleVisibility: .visible
        ) {
            ForEach(downloadOptions) { plan in
                Button(plan.label) {
                    downloader.start(
                        board: store.board,
                        posts: store.posts,
                        kind: plan.kind,
                        environment: .shared
                    )
                }
                .disabled(plan.isEmpty)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Already-downloaded files are skipped, so an interrupted download resumes by running it again. Thread text is saved automatically when you bookmark.")
        }
        .safeAreaInset(edge: .top) {
            if downloader.isRunning {
                DownloadProgressBar(progress: downloader.progress) { downloader.cancel() }
            }
        }
        .task {
            await store.loadIfNeeded()
            // Only after the posts exist, otherwise the scroll request would be
            // dropped before the cell it targets is in the snapshot.
            if let initialPost { pendingScroll = initialPost }
            store.refreshUserState()

            // Live thread: poll the tail endpoint while the screen is visible.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                await store.pollForNewPosts()
            }
        }
        .sheet(item: $viewer) { request in
            MediaViewerScreen(board: store.board, items: request.items, start: request.index)
        }
    }
}

// MARK: - Media viewer

public struct MediaViewerScreen: View {
    public let board: BoardID
    /// One file when opened from a post, the whole thread when opened from the
    /// gallery. More than one is what makes the viewer pageable.
    let items: [ThreadGalleryItem]

    @State private var index: Int
    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(board: BoardID, post: Post) {
        self.board = board
        self.items = post.attachment.map {
            [ThreadGalleryItem(postNumber: post.no, attachment: $0)]
        } ?? []
        _index = State(initialValue: 0)
    }

    init(board: BoardID, items: [ThreadGalleryItem], start: Int) {
        self.board = board
        self.items = items
        _index = State(initialValue: items.isEmpty ? 0 : min(max(start, 0), items.count - 1))
    }

    private var current: ThreadGalleryItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.count > 1 {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        page(item).tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else if let item = items.first {
                page(item)
            }
        }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .topLeading) { counter }
        .overlay(alignment: .bottom) { caption }
    }

    @ViewBuilder
    private func page(_ item: ThreadGalleryItem) -> some View {
        let attachment = item.attachment
        if attachment.isVideo {
            videoView(attachment)
        } else if attachment.isAnimated {
            ChanGIFImage(url: mediaURL(for: attachment))
        } else {
            ZoomableImageView(url: mediaURL(for: attachment))
        }
    }

    @ViewBuilder
    private var counter: some View {
        if items.count > 1 {
            Text("\(index + 1) of \(items.count)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(ChanSpacing.l)
        }
    }

    private var closeButton: some View {
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

    /// Prefers the downloaded copy, so a saved thread opens offline.
    private func mediaURL(for attachment: Attachment) -> URL {
        SavedMediaStore.localURL(board: board, tim: attachment.tim, ext: attachment.ext)
            ?? ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext)
    }

    @ViewBuilder
    private func videoView(_ attachment: Attachment) -> some View {
        let url = mediaURL(for: attachment)
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
        if let attachment = current?.attachment {
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

/// A thin bar above the timeline while media downloads.
private struct DownloadProgressBar: View {
    let progress: MediaDownloader.Progress
    let onCancel: () -> Void

    @Environment(\.chanTheme) private var theme

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: ChanSpacing.s) {
                ProgressView(value: progress.fraction)
                    .tint(theme.accent)
                Text(progress.summary)
                    .font(.caption2)
                    .foregroundColor(theme.secondaryText)
                    .fixedSize()
                Button {
                    ChanHaptics.tap()
                    onCancel()
                } label: {
                    Text("Stop")
                        .font(.caption2.weight(.semibold))
                }
                .tint(theme.danger)
            }
            if progress.bytes > 0 {
                Text("\(ChanFormat.bytes(progress.bytes)) downloaded")
                    .font(.caption2)
                    .foregroundColor(theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, ChanSpacing.m)
        .padding(.vertical, ChanSpacing.s)
        .background(.bar)
    }
}

/// An explicit search field, shown only while a search is active.
///
/// Used instead of `.searchable` because a SwiftUI search bar cannot detect the
/// scroll view inside a bridged UIKit collection view, so it never auto-hides
/// and stayed pinned over the content permanently.
struct ChanSearchBar: View {
    let placeholder: String
    @Binding var text: String
    let onCancel: () -> Void

    @Environment(\.chanTheme) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: ChanSpacing.s) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(theme.tertiaryText)

                TextField(placeholder, text: $text)
                    .focused($focused)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(theme.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: ChanRadius.small, style: .continuous))

            Button("Cancel") { onCancel() }
                .font(.footnote.weight(.semibold))
                .tint(theme.accent)
        }
        .padding(.horizontal, ChanSpacing.m)
        .padding(.vertical, ChanSpacing.s)
        .background(.bar)
        .onAppear { focused = true }
    }
}

/// Which representation of a thread is showing.
enum ThreadMode {
    case list
    case gallery
}

/// A viewer presentation: one file from the list, or the whole thread from the
/// gallery. `items` carries the ordered set so the viewer can page through it.
struct ViewerRequest: Identifiable {
    let id = UUID()
    let items: [ThreadGalleryItem]
    let index: Int
}
