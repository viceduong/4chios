import ChanCore
import ChanMedia
import ChanUI
import SwiftUI

public struct SettingsScreen: View {
    @ObservedObject var settings: ChanSettings

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var cacheCleared = false

    public init(settings: ChanSettings) {
        self.settings = settings
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
                        Text(ChanVersion.current).foregroundColor(theme.secondaryText)
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
