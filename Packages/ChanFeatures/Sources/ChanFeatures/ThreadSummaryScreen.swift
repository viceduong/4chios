import ChanAI
import ChanCore
import ChanUI
import SwiftUI

/// The AI summary of a thread.
///
/// One tap on the toolbar button is all it takes: this screen opens already
/// summarizing, shows a cached summary instantly when it has one, and keeps the
/// style/regenerate controls out of the way in the toolbar menu.
public struct ThreadSummaryScreen: View {
    @ObservedObject private var store: ThreadSummaryStore
    private let posts: [Post]

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(store: ThreadSummaryStore, posts: [Post]) {
        self.store = store
        self.posts = posts
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: ChanSpacing.l) {
                    content

                    if let summary = store.summary {
                        footer(summary)
                    }
                }
                .padding(ChanSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Thread summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .navigationViewStyle(.stack)
        .onAppear { store.start(posts: posts) }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if store.phase.isWorking {
                Button("Cancel") { store.cancel() }
                    .tint(theme.danger)
            } else {
                Menu {
                    Section("Style") {
                        ForEach(SummaryStyle.allCases) { style in
                            Button {
                                store.style = style
                                store.summarize(posts: posts)
                            } label: {
                                if store.style == style {
                                    Label(style.label, systemImage: "checkmark")
                                } else {
                                    Text(style.label)
                                }
                            }
                        }
                    }

                    Button {
                        store.summarize(posts: posts)
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }

                    if store.summary != nil {
                        Button(role: .destructive) {
                            store.clear()
                            store.summarize(posts: posts)
                        } label: {
                            Label("Clear and regenerate", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(theme.accent)
                .disabled(!store.isConfigured)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !store.isConfigured {
            notice("Add a General Compute API key in Settings to summarize threads.", color: theme.danger)
        }

        switch store.phase {
        case .idle:
            EmptyView()

        case let .working(status):
            VStack(alignment: .leading, spacing: ChanSpacing.m) {
                HStack(spacing: ChanSpacing.m) {
                    ProgressView().tint(theme.accent)
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(theme.primaryText)
                }
                if let summary = store.summary {
                    // Keep the previous summary readable while it refreshes.
                    summaryText(summary.text).opacity(0.5)
                }
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: ChanSpacing.s) {
                notice(message, color: theme.danger)
                Button {
                    store.summarize(posts: posts)
                } label: {
                    Text("Try again").font(.footnote.weight(.semibold))
                }
                .tint(theme.accent)
                .disabled(!store.isConfigured)
            }

        case .ready:
            if let summary = store.summary {
                VStack(alignment: .leading, spacing: ChanSpacing.m) {
                    if store.isStale {
                        notice("New posts have arrived since this summary.", color: theme.accent)
                    }
                    summaryText(summary.text)
                }
            }
        }
    }

    private func summaryText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundColor(theme.primaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer(_ summary: ThreadSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().padding(.vertical, 4)
            Text("\(summary.model)  ·  \(summary.postCount) posts")
                .font(.caption2)
                .foregroundColor(theme.tertiaryText)
            Text("Generated \(ChanFormat.relative(summary.generatedAt)). Only post text is sent; images and videos are never uploaded.")
                .font(.caption2)
                .foregroundColor(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(color)
            .padding(ChanSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: ChanRadius.small, style: .continuous))
    }
}
