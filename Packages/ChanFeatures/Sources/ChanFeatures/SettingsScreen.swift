import ChanAI
import ChanCore
import ChanMedia
import ChanUI
import SwiftUI

public struct SettingsScreen: View {
    @ObservedObject var settings: ChanSettings
    @ObservedObject private var usage = AppEnvironment.shared.usage
    @State private var savedMediaBytes = 0
    @State private var savedMediaFiles = 0

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var cacheCleared = false

    public init(settings: ChanSettings) {
        self.settings = settings
    }

    /// Version and build together. The version alone cannot tell two builds of
    /// the same release apart, which is what makes "am I running the fix?"
    /// answerable from the app rather than from the release notes.
    private var buildStamp: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(ChanVersion.current) (\(build))"
    }

    public var body: some View {
        NavigationView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.themeMode) {
                        ForEach(ChanSettings.ThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }

                    HStack {
                        Text("Font size")
                        Slider(value: $settings.fontSize, in: 12...22, step: 1)
                        Text("\(Int(settings.fontSize))")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(theme.secondaryText)
                            .frame(width: 24, alignment: .trailing)
                    }

                    Toggle("Show thumbnails", isOn: $settings.showThumbnails)
                }

                Section("Favorites") {
                    if settings.favoriteBoards.isEmpty {
                        Text("Star a board from the list to pin it here.")
                            .font(.footnote)
                            .foregroundColor(theme.secondaryText)
                    } else {
                        ForEach(settings.favoriteBoards, id: \.self) { board in
                            Text("/\(board.rawValue)/")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                settings.toggleFavorite(settings.favoriteBoards[index])
                            }
                        }
                    }
                }

                Section("AI summaries") {
                    TextField("Endpoint", text: $settings.aiEndpoint)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.footnote, design: .monospaced))
                    TextField("Model", text: $settings.aiModel)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.footnote, design: .monospaced))
                    SecureField("API key", text: $settings.aiAPIKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if settings.isAIConfigured {
                        Label("Ready", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(theme.accent)
                    } else {
                        Label("Add a key to enable summaries", systemImage: "key")
                            .font(.caption)
                            .foregroundColor(theme.danger)
                    }

                    Text("Summaries send this thread's post text to the endpoint above. Images and videos are never uploaded. The key is kept in the Keychain, never in preferences.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)
                }

                Section("Web search") {
                    SecureField("Exa API key (preferred)", text: $settings.aiExaAPIKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Label(
                        settings.hasDirectSearch
                            ? "Searching directly through Exa"
                            : "Add an Exa key to use their free monthly allowance",
                        systemImage: settings.hasDirectSearch ? "checkmark.seal.fill" : "key"
                    )
                    .font(.caption)
                    .foregroundColor(settings.hasDirectSearch ? theme.accent : theme.secondaryText)
                    Text("Called directly, so searches bill against Exa's own free tier rather than a reseller. Takes precedence over OpenRouter when set.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)

                    SecureField("OpenRouter API key", text: $settings.aiSearchAPIKey)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Model", text: $settings.aiSearchModel)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.footnote, design: .monospaced))
                    TextField("Endpoint", text: $settings.aiSearchEndpoint)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(.footnote, design: .monospaced))

                    Picker("Search when", selection: $settings.aiSearchMode) {
                        ForEach(AISearchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    Text(settings.aiSearchMode.detail)
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)

                    Picker("Engine", selection: $settings.aiSearchEngine) {
                        ForEach(AISearchEngine.allCases) { engine in
                            Text("\(engine.label) - \(engine.costLabel)").tag(engine)
                        }
                    }
                    Text("\(settings.aiSearchEngine.detail) Each search includes up to 10 results for the same fee, and the fee is charged per search, not per result.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)

                    Label(
                        settings.canSearchTheWeb ? "Chat can search the web" : "Add a key to let chat search the web",
                        systemImage: settings.canSearchTheWeb ? "globe" : "key"
                    )
                    .font(.caption)
                    .foregroundColor(settings.canSearchTheWeb ? theme.accent : theme.secondaryText)

                    Text("When you ask a follow-up that needs current information, the question and the thread's text are sent to this endpoint, which searches the web and returns cited results.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)
                }

                Section("Offline media") {
                    HStack {
                        Text("Downloaded")
                        Spacer()
                        Text(ChanFormat.bytes(savedMediaBytes))
                            .foregroundColor(theme.secondaryText)
                    }
                    HStack {
                        Text("Files")
                        Spacer()
                        Text("\(savedMediaFiles)")
                            .foregroundColor(theme.secondaryText)
                    }
                    if savedMediaBytes > 0 {
                        Button(role: .destructive) {
                            try? AppEnvironment.shared.database.deleteAllMediaRecords()
                            try? SavedMediaStore.delete()
                            savedMediaBytes = 0
                            savedMediaFiles = 0
                            ChanHaptics.warning()
                        } label: {
                            Text("Delete all downloaded media")
                        }
                    }
                    Text("Thread text is saved automatically when you bookmark. Media is downloaded only when you ask for it, from the download button in a thread.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)
                }

                Section("AI usage") {
                    HStack {
                        Text("Tokens used")
                        Spacer()
                        Text(usage.formattedTotalTokens)
                            .foregroundColor(theme.secondaryText)
                    }
                    HStack {
                        Text("Requests")
                        Spacer()
                        Text("\(usage.snapshot.requests)")
                            .foregroundColor(theme.secondaryText)
                    }
                    if let spend = usage.estimatedSpend {
                        HStack {
                            Text("Estimated spend")
                            Spacer()
                            Text(AIPricing.format(spend))
                                .foregroundColor(theme.secondaryText)
                        }
                    }
                    if let last = usage.snapshot.lastUsedAt {
                        HStack {
                            Text("Last used")
                            Spacer()
                            Text(ChanFormat.relative(last))
                                .foregroundColor(theme.secondaryText)
                        }
                    }
                    if usage.hasUnpricedUsage {
                        Text("General Compute does not publish a price for every model, so no dollar estimate is shown for those tokens.")
                            .font(.caption2)
                            .foregroundColor(theme.secondaryText)
                    }

                    if settings.hasDirectSearch {
                        HStack {
                            Text("Search spend")
                            Spacer()
                            Text(AIPricing.format(usage.measuredSearchSpend))
                                .foregroundColor(theme.secondaryText)
                        }
                    }

                    if !settings.hasDirectSearch, settings.canSearchTheWeb {
                        HStack {
                            Text("OpenRouter balance")
                            Spacer()
                            if usage.isLoadingBalance {
                                ProgressView()
                            } else if let balance = usage.searchBalance {
                                Text(balance.formattedRemaining)
                                    .foregroundColor(balance.isOverdrawn ? theme.danger : theme.secondaryText)
                            } else {
                                Text("unavailable").foregroundColor(theme.tertiaryText)
                            }
                        }

                        if let balance = usage.searchBalance, balance.isOverdrawn {
                            Text("This balance is spent. Search endpoints often keep serving into a small negative balance, then start returning 402 and search stops working. Top up or point the endpoint elsewhere.")
                                .font(.caption2)
                                .foregroundColor(theme.danger)
                        }
                        if let error = usage.balanceError {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(theme.danger)
                        }
                    }

                    Link(destination: URL(string: "https://app.generalcompute.com")!) {
                        Label("Check your credit balance", systemImage: "arrow.up.right.square")
                    }

                    Text("The General Compute API has no billing endpoint, so a credit balance cannot be fetched. These figures are usage tracked on this device; the dashboard shows the real balance.")
                        .font(.caption2)
                        .foregroundColor(theme.secondaryText)

                    if usage.snapshot.requests > 0 {
                        Button(role: .destructive) {
                            usage.reset()
                        } label: {
                            Text("Reset usage counters")
                        }
                    }
                }

                Section("Filters") {
                    NavigationLink(destination: FiltersScreen()) {
                        Label("Content filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                Section("Cache") {
                    Button(cacheCleared ? "Image cache cleared" : "Clear image cache") {
                        ChanImagePipeline.clearCaches()
                        cacheCleared = true
                        ChanHaptics.success()
                    }
                    .disabled(cacheCleared)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(buildStamp).foregroundColor(theme.secondaryText)
                    }
                    HStack {
                        Text("Schema")
                        Spacer()
                        Text("\(ChanVersion.schemaVersion)").foregroundColor(theme.secondaryText)
                    }
                    Link("Data provided by 4chan", destination: URL(string: "https://www.4chan.org")!)
                    Text("4chios is an unofficial client. It is not affiliated with or endorsed by 4chan, and it respects the 1 request/second API limit.")
                        .font(.caption)
                        .foregroundColor(theme.secondaryText)
                }
            }
            .onAppear {
                savedMediaBytes = SavedMediaStore.bytesOnDisk()
                savedMediaFiles = (try? AppEnvironment.shared.database.mediaRecordCount()) ?? 0
            }
            .task {
                await usage.refreshSearchBalance(
                    endpoint: settings.aiSearchEndpoint,
                    apiKey: settings.aiSearchAPIKey
                )
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
