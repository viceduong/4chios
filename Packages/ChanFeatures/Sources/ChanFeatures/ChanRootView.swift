import ChanCore
import ChanUI
import SwiftUI

/// The composition root of the feature layer. The app target stays deliberately thin
/// and only injects the environment; every screen hangs off this view.
public struct ChanRootView: View {
    @Environment(\.chanTheme) private var theme

    public init() {}

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: ChanSpacing.m) {
                Text("4chios")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(theme.primaryText)

                Text("v\(ChanVersion.current) · schema \(ChanVersion.schemaVersion)")
                    .font(.footnote.monospaced())
                    .foregroundColor(theme.secondaryText)

                Text("M0 scaffold online — data layer lands next")
                    .font(.subheadline)
                    .foregroundColor(theme.accent)
                    .padding(.top, ChanSpacing.s)
            }
            .padding(ChanSpacing.xl)
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
