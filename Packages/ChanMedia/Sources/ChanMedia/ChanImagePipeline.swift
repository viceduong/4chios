import Foundation
import Nuke

/// The shared image pipeline: memory + disk cache, request coalescing, and
/// downsampling tuned for a phone that is scrolling a thread full of images.
public enum ChanImagePipeline {
    /// Total decoded-image memory budget.
    public static let memoryCostLimit = 256 * 1024 * 1024
    /// On-disk raw-data budget.
    public static let diskSizeLimit = 512 * 1024 * 1024

    public static let shared: ImagePipeline = {
        var configuration = ImagePipeline.Configuration()

        configuration.imageCache = ImageCache(costLimit: memoryCostLimit, countLimit: 750)

        if let dataCache = try? DataCache(name: "com.viceduong.ch4ios.images") {
            dataCache.sizeLimit = diskSizeLimit
            configuration.dataCache = dataCache
        }

        // Cache every successful response; 4chan media is immutable once posted.
        configuration.dataCachePolicy = .automatic
        configuration.isProgressiveDecodingEnabled = true
        configuration.isTaskCoalescingEnabled = true

        return ImagePipeline(configuration: configuration)
    }()

    /// Prefetches a batch of URLs, e.g. the next screenful of a catalog.
    public static func prefetch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.startPrefetching(with: urls)
    }

    /// Cancels prefetching for URLs that scrolled out of range.
    public static func stopPrefetching(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        prefetcher.stopPrefetching(with: urls)
    }

    /// Shared prefetcher; Nuke coalesces and prioritises requests internally.
    public static let prefetcher = ImagePrefetcher(pipeline: shared)

    /// Wipes both caches. Used by the "clear image cache" settings row.
    public static func clearCaches() {
        shared.cache.removeAll()
        shared.configuration.dataCache?.removeAll()
    }
}
