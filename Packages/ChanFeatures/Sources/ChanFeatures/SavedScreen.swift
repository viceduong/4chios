import ChanCore
import ChanMedia
import ChanUI
import SwiftUI

/// Everything the reader kept, split by what it is.
public struct SavedScreen: View {
    public enum Category: String, CaseIterable, Identifiable {
        case threads
        case posts
        case media

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .threads: return "Threads"
            case .posts: return "Posts"
            case .media: return "Media"
            }
        }
    }

    @StateObject private var store = SavedStore(environment: .shared)
    @State private var category: Category = .threads
    @State private var viewingMedia: SavedMediaItem?

    @Environment(\.chanTheme) private var theme

    public init() {}

    public var body: some View {
        // The picker sits above the list rather than in a safe-area inset: an
        // inset floats over the scroll view, so the list's own content slid
        // under it and the two overlapped.
        VStack(spacing: 0) {
            Picker("Category", selection: $category) {
                ForEach(Category.allCases) { category in
                    Text(category.label).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, ChanSpacing.l)
            .padding(.vertical, ChanSpacing.s)
            .background(theme.background)

            List {
                switch category {
                case .threads: threadSections
                case .posts: postSection
                case .media: mediaSection
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Saved")
        .onAppear { store.load() }
        .refreshable { store.load() }
        .sheet(item: $viewingMedia) { item in
            SavedMediaViewerScreen(item: item)
                .environment(\.chanTheme, theme)
        }
    }

    // MARK: - Threads

    @ViewBuilder
    private var threadSections: some View {
        if store.bookmarks.isEmpty, store.watched.isEmpty {
            emptyState(
                "Nothing saved yet",
                "Open a thread and tap the bookmark or eye button to keep track of it here."
            )
        }

        if !store.watched.isEmpty {
            Section("Watching") {
                ForEach(store.watched) { threadRow($0) }
            }
        }

        if !store.bookmarks.isEmpty {
            Section("Bookmarked") {
                ForEach(store.bookmarks) { threadRow($0) }
            }
        }
    }

    @ViewBuilder
    private func threadRow(_ thread: SavedThread) -> some View {
        NavigationLink(destination: ThreadScreen(board: thread.board, op: thread.op)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    boardTag(thread.board)
                    if thread.unreadReplies > 0 {
                        ChanTag(text: "\(thread.unreadReplies) NEW", color: theme.danger)
                    }
                    Spacer()
                    Text(ChanFormat.relative(thread.addedAt))
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText)
                }

                Text(thread.title)
                    .font(.subheadline)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(2)

                Text("R: \(ChanFormat.count(thread.replies))   I: \(ChanFormat.count(thread.images))")
                    .font(.caption2)
                    .foregroundColor(theme.secondaryText)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(theme.surface)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(thread)
                ChanHaptics.warning()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Posts

    @ViewBuilder
    private var postSection: some View {
        if store.posts.isEmpty {
            emptyState(
                "No saved posts",
                "Long press any post in a thread and choose Bookmark post. Its text is stored, so it reads offline too."
            )
        } else {
            Section("Posts") {
                ForEach(store.posts) { post in
                    NavigationLink(
                        destination: ThreadScreen(
                            board: post.board,
                            op: post.threadNumber,
                            initialPost: post.postNumber
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                boardTag(post.board)
                                Text("#\(post.postNumber.value)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(theme.tertiaryText)
                                Spacer()
                                Text(ChanFormat.relative(post.addedAt))
                                    .font(.caption2)
                                    .foregroundColor(theme.tertiaryText)
                            }

                            Text(post.threadTitle)
                                .font(.caption)
                                .foregroundColor(theme.secondaryText)
                                .lineLimit(1)

                            Text(post.snippet)
                                .font(.subheadline)
                                .foregroundColor(theme.primaryText)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowBackground(theme.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.remove(post)
                            ChanHaptics.warning()
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Media

    @ViewBuilder
    private var mediaSection: some View {
        if store.media.isEmpty {
            emptyState(
                "No saved media",
                "Long press a post with a file and choose Save media. The file is downloaded, so it opens with no network."
            )
        } else {
            Section {
                ForEach(store.media) { item in
                    Button {
                        viewingMedia = item
                    } label: {
                        mediaRow(item)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.surface)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.remove(item)
                            ChanHaptics.warning()
                        } label: {
                            Label("Delete file", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("\(store.media.count) files, \(ChanFormat.bytes(store.media.reduce(0) { $0 + $1.byteCount }))")
            }
        }
    }

    private func mediaRow(_ item: SavedMediaItem) -> some View {
        HStack(spacing: ChanSpacing.m) {
            // The thumbnail comes from the downloaded file, so this list works
            // with no network at all.
            ZStack {
                RoundedRectangle(cornerRadius: ChanRadius.small, style: .continuous)
                    .fill(theme.elevated)
                if !item.isVideo {
                    ChanRemoteImage(url: item.localURL, scaling: .fill, cornerRadius: ChanRadius.small)
                } else {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(theme.secondaryText)
                }
            }
            .frame(width: 52, height: 52)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    boardTag(item.board)
                    ChanTag(
                        text: item.isVideo ? "VIDEO" : "IMAGE",
                        color: item.isVideo ? theme.danger : theme.secondaryText
                    )
                    Spacer()
                    Text(ChanFormat.relative(item.addedAt))
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText)
                }

                Text("\(item.filename)\(item.ext)")
                    .font(.subheadline)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                Text(ChanFormat.bytes(item.byteCount))
                    .font(.caption2)
                    .foregroundColor(theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Shared

    private func boardTag(_ board: BoardID) -> some View {
        Text("/\(board.rawValue)/")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(theme.accent)
    }

    private func emptyState(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: ChanSpacing.s) {
            Text(title)
                .font(.headline)
                .foregroundColor(theme.primaryText)
            Text(detail)
                .font(.footnote)
                .foregroundColor(theme.secondaryText)
        }
        .padding(.vertical, ChanSpacing.s)
        .listRowBackground(theme.surface)
    }
}
