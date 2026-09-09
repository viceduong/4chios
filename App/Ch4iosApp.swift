import ChanFeatures
import ChanUI
import SwiftUI

@main
struct Ch4iosApp: App {
    var body: some Scene {
        WindowGroup {
            ChanRootView()
                .environment(\.chanTheme, .dark)
        }
    }
}
