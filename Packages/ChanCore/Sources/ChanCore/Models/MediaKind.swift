import Foundation

/// What kind of media a post attachment is, derived from its file extension.
///
/// Pure logic, so it lives in the domain layer and is tested in the fast lane.
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
        case "jpg", "jpeg", "png", "webp": self = .image
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
