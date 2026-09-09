import ChanFeatures
import SwiftUI

@main
struct Ch4iosApp: App {
    @UIApplicationDelegateAdaptor(ChanAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ChanRootView()
        }
    }
}
