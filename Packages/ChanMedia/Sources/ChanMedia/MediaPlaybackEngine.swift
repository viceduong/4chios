import Foundation

/// A playback surface for formats AVFoundation cannot decode on iOS 15
/// (VP8/VP9 `.webm`). Implemented by the VLCKit engine and consumed by the
/// gallery behind this protocol, so the dependency stays swappable.
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
