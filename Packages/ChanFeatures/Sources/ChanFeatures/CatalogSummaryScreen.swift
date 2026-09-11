import ChanAI
import ChanCore
import ChanUI
import SwiftUI

/// Reads a whole board and shows what is going on.
///
/// Presented as a sheet with its own navigation, so a thread named in the digest
/// can be opened without disturbing where the reader was in the catalog.
public struct CatalogSummaryScreen: View {
    public let board: BoardID
    let threads: [Post]

    @StateObject private var store: CatalogSummaryStore
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @Environment(\.chanTheme) private var theme

    public init(board: BoardID, threads: [Post]) {
        self.board = board
        self.threads = threads
        _store = StateObject(wrappedValue: CatalogSummaryStore(board: board, environment: .shared))
    }

    public var body: some View {
        NavigationView {
            Group {
                switch store.phase {
                case .idle, .working:
                    working
                case .failed(let message):
                    failure(message)
                case .ready:
                    content
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("/\(board.rawValue)/ digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            store.summarize(threads: threads)
                        } label: {
                            Label("Read it again", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            store.clear()
                        } label: {
                            Label("Clear digest", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .tint(theme.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { store.start(threads: threads) }
        .onDisappear { store.cancel() }
    }

    // MARK: - States

    private var working: some View {
        VStack(spacing: ChanSpacing.m) {
            ProgressView()
            Text(statusText)
                .font(.footnote)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Cancel") { store.cancel() }
                .font(.footnote.weight(.semibold))
                .tint(theme.accent)
        }
        .padding(ChanSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if case .working(let status) = store.phase { return status }
        return "Starting…"
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: ChanSpacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(theme.danger)
            Text(message)
                .font(.footnote)
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again") { store.summarize(threads: threads) }
                .font(.footnote.weight(.semibold))
                .tint(theme.accent)
        }
        .padding(ChanSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let summary = store.summary {
            List {
                if store.isStale {
                    Section {
                        HStack(spacing: ChanSpacing.s) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(theme.danger)
                            Text("The board has changed since this was written.")
                                .font(.caption)
                                .foregroundColor(theme.secondaryText)
                        }
                    }
                    .listRowBackground(theme.surface)
                }

                Section("Overview") {
                    MarkdownText(
                        summary.overview.isEmpty ? "(no overview)" : summary.overview,
                        fontSize: settings.fontSize
                    )
                    .listRowBackground(theme.surface)
                }

                if !summary.threads.isEmpty {
                    Section("Worth a look") {
                        ForEach(summary.threads) { thread in
                            NavigationLink {
                                ThreadScreen(board: board, op: thread.number)
                            } label: {
                                HStack(alignment: .top, spacing: ChanSpacing.s) {
                                    Text("#\(thread.number.value)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(theme.accent)
                                    MarkdownText(thread.line, fontSize: 15)
                                }
                                .padding(.vertical, 2)
                            }
                            .listRowBackground(theme.surface)
                        }
                    }
                }

                Section {
                    Text(footer(for: summary))
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText)
                }
                .listRowBackground(theme.surface)
            }
            .listStyle(.insetGrouped)
        }
    }

    private func footer(for summary: CatalogSummary) -> String {
        let count = summary.threadCount
        return "Read \(count) thread\(count == 1 ? "" : "s") with \(summary.model) on "
            + ChanFormat.relative(summary.generatedAt)
            + ". Only what the catalog listing states is used."
    }
}
