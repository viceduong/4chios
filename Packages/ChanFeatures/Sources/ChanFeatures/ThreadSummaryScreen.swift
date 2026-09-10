import ChanAI
import ChanCore
import ChanUI
import SwiftUI

/// The AI summary of a thread, with tappable citations back into the timeline.
public struct ThreadSummaryScreen: View {
    @ObservedObject private var store: ThreadSummaryStore
    private let posts: [Post]
    private let onJump: (PostNumber) -> Void

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(store: ThreadSummaryStore, posts: [Post], onJump: @escaping (PostNumber) -> Void) {
        self.store = store
        self.posts = posts
        self.onJump = onJump
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: ChanSpacing.l) {
                    if !store.isConfigured {
                        notice(
                            "Add a General Compute API key in Settings to summarize threads.",
                            color: theme.danger
                        )
                    }

                    stylePicker
                    content

                    if let summary = store.summary, !summary.citedPosts.isEmpty {
                        citations(summary.citedPosts)
                    }

                    if let summary = store.summary {
                        footer(summary)
                    }
                }
                .padding(ChanSpacing.l)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Thread summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.phase.isWorking {
                        Button("Cancel") { store.cancel() }
                            .tint(theme.danger)
                    } else {
                        Button {
                            store.summarize(posts: posts)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .tint(theme.accent)
                        .disabled(!store.isConfigured)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            store.loadCached(posts: posts)
            if store.summary == nil { store.summarize(posts: posts) }
        }
    }

    // MARK: - Sections

    private var stylePicker: some View {
        Picker("Style", selection: $store.style) {
            ForEach(SummaryStyle.allCases) { style in
                Text(style.label).tag(style)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: store.style) { _ in
            store.summarize(posts: posts)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle:
            EmptyView()

        case let .working(status):
            HStack(spacing: ChanSpacing.m) {
                ProgressView().tint(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(theme.primaryText)
                    Text("A long thread is summarized in parts, so this can take a minute.")
                        .font(.caption2)
                        .foregroundColor(theme.tertiaryText)
                }
            }
            .padding(ChanSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: ChanRadius.medium, style: .continuous))

        case let .failed(message):
            VStack(alignment: .leading, spacing: ChanSpacing.s) {
                notice(message, color: theme.danger)
                Button("Try again") { store.summarize(posts: posts) }
                    .font(.footnote.weight(.semibold))
                    .tint(theme.accent)
            }

        case .ready:
            if let summary = store.summary {
                VStack(alignment: .leading, spacing: ChanSpacing.s) {
                    if store.isStale {
                        notice("New posts have arrived since this summary. Refresh it to include them.", color: theme.accent)
                    }
                    Text(summary.text)
                        .font(.system(size: 15))
                        .foregroundColor(theme.primaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func citations(_ numbers: [PostNumber]) -> some View {
        VStack(alignment: .leading, spacing: ChanSpacing.s) {
            Text("CITED POSTS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.tertiaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(numbers, id: \.self) { number in
                        Button {
                            ChanHaptics.tap()
                            onJump(number)
                        } label: {
                            Text(">>\(number.value)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(theme.elevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func footer(_ summary: ThreadSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Divider().padding(.vertical, 4)
            Text("\(summary.model)  ·  \(summary.postCount) posts  ·  \(summary.chunkCount) request\(summary.chunkCount == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(theme.tertiaryText)
            if summary.imageCount > 0 {
                Text("\(summary.imageCount) image\(summary.imageCount == 1 ? "" : "s") sent for description")
                    .font(.caption2)
                    .foregroundColor(theme.tertiaryText)
            }
            Text("Generated \(ChanFormat.relative(summary.generatedAt)). Post text is sent to General Compute when you request a summary.")
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
