import ChanCore
import ChanUI
import SwiftUI

/// Bookmarks and watched threads, with unread reply counts.
public struct SavedScreen: View {
    @StateObject private var store = SavedStore(environment: .shared)
    @Environment(\.chanTheme) private var theme

    public init() {}

    public var body: some View {
        List {
            if store.bookmarks.isEmpty, store.watched.isEmpty {
                VStack(alignment: .leading, spacing: ChanSpacing.s) {
                    Text("Nothing saved yet")
                        .font(.headline)
                        .foregroundColor(theme.primaryText)
                    Text("Open a thread and tap the bookmark or eye button to keep track of it here.")
                        .font(.footnote)
                        .foregroundColor(theme.secondaryText)
                }
                .padding(.vertical, ChanSpacing.s)
                .listRowBackground(theme.surface)
            }

            if !store.watched.isEmpty {
                Section("Watching") {
                    ForEach(store.watched) { row($0) }
                }
            }

            if !store.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(store.bookmarks) { row($0) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Saved")
        .onAppear { store.load() }
        .refreshable { store.load() }
    }

    @ViewBuilder
    private func row(_ thread: SavedThread) -> some View {
        NavigationLink(destination: ThreadScreen(board: thread.board, op: thread.op)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("/\(thread.board.rawValue)/")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(theme.accent)
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

                Text("R: \(ChanFormat.count(thread.replies))  I: \(ChanFormat.count(thread.images))")
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
}
