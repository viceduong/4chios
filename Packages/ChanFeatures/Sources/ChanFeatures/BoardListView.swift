import ChanCore
import ChanUI
import SwiftUI

/// The board list: favorites first, then every board, with search.
public struct BoardListView: View {
    @ObservedObject private var store: BoardListStore
    @ObservedObject private var settings: ChanSettings
    @Environment(\.chanTheme) private var theme
    @State private var query = ""

    public init(store: BoardListStore, settings: ChanSettings) {
        self.store = store
        self.settings = settings
    }

    public var body: some View {
        List {
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { row($0) }
                }
            }

                Section("Boards") {
                    ForEach(others) { row($0) }
                }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search boards")
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
        .navigationTitle("4chios")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .center) {
            if store.boards.isEmpty, store.isLoading {
                ProgressView().tint(theme.accent)
            } else if let message = store.errorMessage, store.boards.isEmpty {
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

    private var visibleBoards: [Board] {
        store.filtered(query: query)
    }

    private var favorites: [Board] {
        visibleBoards.filter { settings.isFavorite($0.board) }
    }

    private var others: [Board] {
        visibleBoards.filter { !settings.isFavorite($0.board) }
    }

    @ViewBuilder
    private func row(_ board: Board) -> some View {
        NavigationLink(destination: CatalogScreen(board: board.board)) {
            HStack(spacing: ChanSpacing.m) {
                Text("/\(board.board.rawValue)/")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundColor(theme.accent)
                    .frame(width: 62, alignment: .leading)

                Text(board.title)
                    .font(.subheadline)
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: ChanSpacing.s)

                if !board.isWorkSafe {
                    ChanTag(text: "NSFW", color: theme.danger)
                }
                if settings.isFavorite(board.board) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(theme.accent)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(theme.surface)
    }
}

/// A small SwiftUI badge that mirrors `ChanTagLabel`.
public struct ChanTag: View {
    public let text: String
    public let color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
