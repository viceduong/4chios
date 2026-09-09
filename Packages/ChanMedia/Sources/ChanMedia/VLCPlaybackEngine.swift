import Foundation
import MobileVLCKit
import SwiftUI
import UIKit

/// WebM (VP8/VP9) playback through VLCKit.
///
/// AVFoundation cannot decode webm on iOS 15, and webm is the dominant 4chan
/// video format. This engine is the only place that touches VLCKit, so the
/// dependency can be swapped or removed without touching feature code.
public final class VLCPlaybackEngine: NSObject, MediaPlaybackEngine {
    private let player = VLCMediaPlayer()

    public override init() {
        super.init()
    }

    /// Renders into the given view. Call before `load(url:)`.
    public func attach(to view: UIView) {
        player.drawable = view
    }

    public func load(url: URL) {
        player.stop()
        player.media = VLCMedia(url: url)
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        player.stop()
    }

    public var isPlaying: Bool {
        player.isPlaying
    }

    /// 0...1 playback position.
    public var position: Float {
        get { player.position }
        set { player.position = newValue }
    }
}

/// SwiftUI surface for the VLC engine.
public struct VLCVideoView: UIViewRepresentable {
    public let url: URL
    public var autoplay: Bool

    public init(url: URL, autoplay: Bool = true) {
        self.url = url
        self.autoplay = autoplay
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.engine.attach(to: view)
        context.coordinator.load(url: url, autoplay: autoplay)
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.load(url: url, autoplay: autoplay)
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.engine.stop()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        let engine = VLCPlaybackEngine()
        private var currentURL: URL?

        func load(url: URL, autoplay: Bool) {
            guard currentURL != url else { return }
            currentURL = url
            engine.load(url: url)
            if autoplay { engine.play() }
        }
    }
}
