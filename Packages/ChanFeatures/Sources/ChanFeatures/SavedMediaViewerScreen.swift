import ChanCore
import ChanMedia
import ChanUI
import SwiftUI

/// Displays or plays a file the reader saved, straight from disk.
///
/// Deliberately lighter than the thread's viewer: a saved item is one file with
/// no post around it, and it must work with no network.
struct SavedMediaViewerScreen: View {
    let item: SavedMediaItem

    @Environment(\.chanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = item.localURL {
                    if item.isVideo {
                        VLCVideoView(url: url)
                    } else if item.kind == .gif {
                        ChanGIFImage(url: url)
                    } else {
                        ZoomableImageView(url: url)
                    }
                } else {
                    VStack(spacing: ChanSpacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                        Text("This file is no longer on the device.")
                            .font(.footnote)
                    }
                    .foregroundColor(.white)
                }
            }
            .navigationTitle(item.filename + item.ext)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("\(ChanFormat.bytes(item.byteCount))  ·  saved \(ChanFormat.relative(item.addedAt))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.vertical, ChanSpacing.s)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .navigationViewStyle(.stack)
    }
}
