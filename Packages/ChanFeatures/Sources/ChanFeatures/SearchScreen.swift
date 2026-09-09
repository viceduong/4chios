import ChanAPI
import ChanCore
import ChanDB
import ChanUI
import SwiftUI

/// Full-text search over everything cached locally (SQLite FTS5).
public struct SearchScreen: View {
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @Environment(\.chanTheme) private var theme

    public init() {}

    public var body: some View {
        List {
            if hits.isEmpty {
                VStack(alignment: .leading, spacing: ChanSpacing.s) {
                    Text(query.isEmpty ? "Search cached posts" : "No matches")
                        .font(.headline)
                        .foregroundColor(theme.primaryText)
                    Text("Search runs against every post you have already loaded, offline and instantly.")
                        .font(.footnote)
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.vertical, ChanSpacing.s)
                .listRowBackground(theme.surface)
            } else {
                ForEach(hits) { hit in
                    NavigationLink(destination: ThreadScreen(board: hit.board, op: hit.threadNumber)) {
                        hitRow(hit)
                    }
                    .listRowBackground(theme.surface)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search posts")
        .navigationTitle("Search")
        .onChange(of: query) { newValue in
            scheduleSearch(newValue)
        }
    }

    private func hitRow(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("/\(hit.board.rawValue)/")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.accent)
                Text("#\(hit.post.no.value)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(theme.tertiaryText)
                Spacer()
                Text(ChanFormat.relative(hit.post.time))
                    .font(.caption2)
                    .foregroundColor(theme.tertiaryText)
            }

            Text(hit.snippet)
                .font(.subheadline)
                .foregroundColor(theme.primaryText)
                .lineLimit(3)
        }
        .padding(.vertical, 2)
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            hits = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? AppEnvironment.shared.database.search(trimmed, limit: 60)) ?? []
            guard !Task.isCancelled else { return }
            hits = results
            isSearching = false
        }
    }
}

extension SearchHit {
    /// The thread this post belongs to (OP itself, or the thread it replied to).
    public var threadNumber: PostNumber {
        post.isOP ? post.no : post.resto
    }

    /// A short plain-text excerpt around the match.
    public var snippet: String {
        let text = PostHTMLParser.parse(post.commentHTML ?? "").plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return post.attachment?.filename ?? "(no text)"
        }
        return text.count > 220 ? String(text.prefix(220)) + "…" : text
    }
}
