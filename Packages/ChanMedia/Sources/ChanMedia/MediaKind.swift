import Foundation

/// What kind of media a post attachment is, derived from its file extension.
///
/// Drives which view renders it: static image, animated image, video, or document.
public enum MediaKind: String, CaseIterable, Sendable {
    case image
    case gif
    case video
    case pdf
    case flash
    case other

    /// Maps a 4chan `ext` value (with or without a leading dot) to a kind.
    public init(ext: String) {
        let normalized = ext.lowercased().drop(while: { $0 == "." })
        switch normalized {
        case "jpg", "jpeg", "png": self = .image
        case "gif": self = .gif
        case "webm", "mp4": self = .video
        case "pdf": self = .pdf
        case "swf": self = .flash
        default: self = .other
        }
    }

    /// True when the kind needs a real decoder rather than a still image loader.
    public var requiresPlaybackEngine: Bool {
        self == .video || self == .flash
    }

    /// True when the content animates on its own.
    public var isAnimated: Bool {
        self == .gif
    }
}

/// A playback surface for video formats AVFoundation cannot decode on iOS 15
/// (VP8/VP9 `.webm`). Implemented by `VLCPlaybackEngine` in M3 and consumed by
/// the gallery behind this protocol so the dependency stays swappable.
public protocol MediaPlaybackEngine: AnyObject {
    /// Replace the current item. Playback does not start until `play()`.
    func load(url: URL)
    /// Start or resume playback.
    func play()
    /// Pause without discarding the item.
    func pause()
    /// Stop and release the current item.
    func stop()
}
