import ChanAI
import ChanCore
import ChanUI
import SwiftUI
import UIKit

/// The AI summary of a thread, and a conversation about it.
///
/// One tap on the toolbar button is all it takes: this screen opens already
/// summarizing, shows a cached summary instantly when it has one, and leaves the
/// summary at the top so follow-up questions have something to point at.
public struct ThreadSummaryScreen: View {
    @ObservedObject private var store: ThreadSummaryStore
    @ObservedObject private var chat: ThreadChatStore
    private let posts: [Post]

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private let bottomAnchor = "chat-bottom"

    public init(store: ThreadSummaryStore, chat: ThreadChatStore, posts: [Post]) {
        self.store = store
        self.chat = chat
        self.posts = posts
    }

    public var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: ChanSpacing.l) {
                        content

                        if let summary = store.summary {
                            footer(summary)
                        }

                        if !chat.turns.isEmpty {
                            Divider()
                            conversation
                        }

                        if chat.isAsking {
                            typingIndicator
                        }

                        if let message = chat.errorMessage {
                            notice(message, color: theme.danger)
                        }

                        // Scroll target, so new answers come into view.
                        Color.clear.frame(height: 1).id(bottomAnchor)
                    }
                    .padding(ChanSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(theme.background.ignoresSafeArea())
                .onChange(of: chat.turns.count) { _ in
                    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
                .onChange(of: chat.isAsking) { isAsking in
                    guard isAsking else { return }
                    withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
            .navigationTitle("Thread summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            store.start(posts: posts)
            chat.prepare(posts: posts, summary: store.summary)
        }
        .onChange(of: store.summary) { summary in
            chat.prepare(posts: posts, summary: summary)
        }
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
                        Label("Regenerate summary", systemImage: "arrow.clockwise")
                    }

                    if !chat.turns.isEmpty {
                        Button(role: .destructive) {
                            chat.clear()
                        } label: {
                            Label("Clear conversation", systemImage: "bubble.left.and.exclamationmark.bubble.right")
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

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: ChanSpacing.s) {
            if chat.canSearch {
                Button {
                    chat.useWebSearch.toggle()
                    ChanHaptics.tap()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(chat.useWebSearch ? .white : theme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(chat.useWebSearch ? theme.accent : Color.clear)
                        .clipShape(Circle())
                }
                .accessibilityLabel(chat.useWebSearch ? "Web search on" : "Web search off")
            }

            TextField("Ask about this thread", text: $draft)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: ChanRadius.large, style: .continuous))

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(canSend ? theme.accent : theme.tertiaryText)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, ChanSpacing.l)
        .padding(.vertical, ChanSpacing.s)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chat.isAsking
    }

    private func send() {
        guard canSend else { return }
        let question = draft
        draft = ""
        ChanHaptics.tap()
        chat.ask(question)
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(alignment: .leading, spacing: ChanSpacing.m) {
            ForEach(chat.turns) { turn in
                turnView(turn)
            }
        }
    }

    @ViewBuilder
    private func turnView(_ turn: ChatTurn) -> some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: ChanSpacing.xl)
                Text(turn.text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: ChanRadius.medium, style: .continuous))
            }

        case .assistant:
            VStack(alignment: .leading, spacing: ChanSpacing.s) {
                if turn.usedWebSearch {
                    Label("Answered with web results", systemImage: "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(theme.tertiaryText)
                }

                Text(turn.text)
                    .font(.system(size: 15))
                    .foregroundColor(theme.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if !turn.sources.isEmpty {
                    sources(turn.sources)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sources(_ sources: [AISource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sources) { source in
                    Button {
                        guard let url = URL(string: source.url) else { return }
                        ChanHaptics.tap()
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9, weight: .bold))
                            Text(hostLabel(source))
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(theme.link)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(theme.elevated)
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func hostLabel(_ source: AISource) -> String {
        guard let host = URL(string: source.url)?.host else { return source.displayTitle }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var typingIndicator: some View {
        HStack(spacing: ChanSpacing.s) {
            ProgressView().tint(theme.accent)
            Text(chat.useWebSearch ? "Searching and thinking…" : "Thinking…")
                .font(.subheadline)
                .foregroundColor(theme.secondaryText)
        }
        .padding(ChanSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ChanRadius.medium, style: .continuous))
    }

    // MARK: - Summary

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
