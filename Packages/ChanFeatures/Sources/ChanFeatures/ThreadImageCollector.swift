import ChanAI
import ChanAPI
import ChanCore
import Foundation
import UIKit

/// Gathers the most relevant thread images and prepares them for the model.
///
/// Photos are only ever sent on an explicit user action, spoilers are never
/// unblurred for the model, and videos are skipped (a still frame from a webm
/// would misrepresent it).
enum ThreadImageCollector {
    static func collect(
        board: BoardID,
        posts: [Post],
        limit: Int,
        maxDimension: CGFloat = 512
    ) async -> [AIImage] {
        let candidates = posts.compactMap { post -> (Post, Attachment)? in
            guard let attachment = post.attachment,
                  !attachment.isVideo,
                  !attachment.isSpoiler,
                  !attachment.isDeleted else { return nil }
            return (post, attachment)
        }
        .prefix(limit)

        var images: [AIImage] = []
        for (post, attachment) in candidates {
            if Task.isCancelled { break }

            // Prefer the ≤1024px preview when 4chan generated one; it is a
            // fraction of the bytes and plenty for description.
            let url = attachment.hasMidSizeImage
                ? ChanMediaURL.preview(board: board, tim: attachment.tim)
                : ChanMediaURL.full(board: board, tim: attachment.tim, ext: attachment.ext)

            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let jpeg = downscaledJPEG(image, maxDimension: maxDimension) else { continue }

            images.append(AIImage(postNumber: post.no, data: jpeg))
        }
        return images
    }

    private static func downscaledJPEG(
        _ image: UIImage,
        maxDimension: CGFloat,
        quality: CGFloat = 0.6
    ) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxDimension / longest)
        let target = CGSize(
            width: max((image.size.width * scale).rounded(), 1),
            height: max((image.size.height * scale).rounded(), 1)
        )

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
