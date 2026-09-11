import ChanAPI
import ChanCore
import ChanMedia
import ChanUI
import SwiftUI

/// One attachment in a thread, in reading order.
struct ThreadGalleryItem: Identifiable, Hashable {
    let postNumber: PostNumber
    let attachment: Attachment

    /// `tim` is unique per file on 4chan, so it identifies the cell.
    var id: Int { attachment.tim }

    var isVideo: Bool { attachment.isVideo }
    var isAnimated: Bool { attachment.isAnimated }
}

/// Every attachment in a thread, as a mosaic.
///
/// SwiftUI rather than a second UIKit collection view on purpose: the cells are
/// uniform squares, so none of the variable-height self-sizing that forced the
/// catalog onto a compositional layout applies here, and `LazyVGrid` gives the
/// same laziness for a fraction of the code.
struct ThreadGalleryView: View {
    let board: BoardID
    let items: [ThreadGalleryItem]
    let onOpen: (Int) -> Void

    @Environment(\.chanTheme) private var theme

    /// Adaptive rather than a fixed count so the mosaic fills an iPad or an SE
    /// without a separate layout.
    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 170), spacing: 2)]

    var body: some View {
        Group {
            if items.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                            Button {
                                ChanHaptics.tap()
                                onOpen(offset)
                            } label: {
                                cell(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .overlay(alignment: .bottom) { summary }
            }
        }
        .background(theme.background)
    }

    // MARK: - Cells

    private func cell(_ item: ThreadGalleryItem) -> some View {
        ZStack {
            Rectangle().fill(theme.elevated)

            if item.attachment.isSpoiler {
                Text("SPOILER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.secondaryText)
            } else {
                ChanRemoteImage(url: thumbnailURL(for: item), scaling: .fill, cornerRadius: 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) { badge(item) }
    }

    /// The local copy when the file has been saved, so the mosaic works offline;
    /// otherwise 4chan's own thumbnail, which is far smaller than the full image
    /// and is what makes a grid this dense viable.
    private func thumbnailURL(for item: ThreadGalleryItem) -> URL? {
        if let saved = SavedMediaStore.localURL(
            board: board,
            tim: item.attachment.tim,
            ext: item.attachment.ext
        ) {
            return saved
        }
        return ChanMediaURL.thumbnail(board: board, tim: item.attachment.tim)
    }

    @ViewBuilder
    private func badge(_ item: ThreadGalleryItem) -> some View {
        if item.isVideo || item.isAnimated {
            HStack(spacing: 3) {
                Image(systemName: item.isVideo ? "play.fill" : "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                if item.isAnimated {
                    Text("GIF").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
            .padding(5)
        }
    }

    // MARK: - Chrome

    private var summary: some View {
        Text(summaryText)
            .font(.caption2)
            .foregroundColor(theme.secondaryText)
            .padding(.horizontal, ChanSpacing.m)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, ChanSpacing.m)
    }

    private var summaryText: String {
        let bytes = items.reduce(0) { $0 + $1.attachment.size }
        let videos = items.filter(\.isVideo).count
        var parts = ["\(items.count) files", ChanFormat.bytes(bytes)]
        if videos > 0 {
            parts.append("\(videos) video\(videos == 1 ? "" : "s")")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var empty: some View {
        VStack(spacing: ChanSpacing.s) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundColor(theme.tertiaryText)
            Text("No media in this thread")
                .font(.subheadline)
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
