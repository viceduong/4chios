import ChanCore
import ChanUI
import SwiftUI

/// The composition root of the feature layer. The app target stays deliberately thin
/// and only injects the environment; every screen hangs off this view.
public struct ChanRootView: View {
    @ObservedObject private var settings = AppEnvironment.shared.settings
    @StateObject private var boardStore = BoardListStore(environment: .shared)

    @Environment(\.chanTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        NavigationView {
            BoardListView(store: boardStore, settings: settings)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            ChanHaptics.tap()
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .tint(theme.accent)
                    }
                }
        }
        .navigationViewStyle(.stack)
        .environment(\.chanTheme, settings.theme(for: colorScheme))
        .tint(settings.theme(for: colorScheme).accent)
        .sheet(isPresented: $showSettings) {
            SettingsScreen(settings: settings)
                .environment(\.chanTheme, settings.theme(for: colorScheme))
        }
    }
}

struct ChanRootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChanRootView().environment(\.chanTheme, .dark)
            ChanRootView().environment(\.chanTheme, .oled)
        }
    }
}
