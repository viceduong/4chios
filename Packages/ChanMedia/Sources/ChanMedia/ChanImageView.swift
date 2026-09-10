import Foundation
import NukeUI
import SwiftUI
import UIKit

/// A UIKit image view built for reused cells.
///
/// Wraps `NukeUI.LazyImageView` with the app's shared pipeline, cancellation on
/// reuse, rounded corners, and — importantly — applies the scaling mode to the
/// *inner* image view. `LazyImageView` itself has no `contentMode`; setting one on
/// the container silently leaves the inner view at UIKit's default
/// `.scaleToFill`, which distorts every image whose aspect ratio differs from its
/// frame.
public final class ChanImageView: UIView {
    /// How the image fills its frame.
    public enum Scaling {
        /// Fill the frame, cropping the overflow. Never distorts. Use in grids.
        case fill
        /// Fit inside the frame, letterboxing. Never distorts or crops. Use for
        /// full-size media and inline attachments.
        case fit
    }

    private let lazyImageView = LazyImageView()
    private var currentURL: URL?

    /// Defaults to `.fill` because cells usually want an edge-to-edge image.
    public var scaling: Scaling = .fill {
        didSet { applyScaling() }
    }

    public var cornerRadius: CGFloat = 8 {
        didSet {
            layer.cornerRadius = cornerRadius
            lazyImageView.layer.cornerRadius = cornerRadius
            clipsToBounds = true
            lazyImageView.clipsToBounds = true
        }
    }

    public var placeholderColor: UIColor = .secondarySystemBackground {
        didSet { backgroundColor = placeholderColor }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        clipsToBounds = true
        backgroundColor = placeholderColor

        lazyImageView.translatesAutoresizingMaskIntoConstraints = false
        lazyImageView.pipeline = ChanImagePipeline.shared
        lazyImageView.clipsToBounds = true
        lazyImageView.layer.cornerRadius = cornerRadius
        lazyImageView.layer.cornerCurve = .continuous
        addSubview(lazyImageView)

        NSLayoutConstraint.activate([
            lazyImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lazyImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            lazyImageView.topAnchor.constraint(equalTo: topAnchor),
            lazyImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        applyScaling()
    }

    private func applyScaling() {
        // The rendering mode belongs to the inner image view, not the wrapper.
        lazyImageView.imageView.contentMode = scaling == .fill ? .scaleAspectFill : .scaleAspectFit
    }

    /// Loads a URL, cancelling whatever was in flight.
    public func load(_ url: URL?, transition: LazyImageView.Transition = .fadeIn(duration: 0.2)) {
        guard url != currentURL else { return }
        currentURL = url
        lazyImageView.transition = transition
        lazyImageView.url = url
    }

    /// Clears the view for cell reuse.
    public func reset() {
        currentURL = nil
        lazyImageView.url = nil
    }
}

/// A SwiftUI wrapper around the same pipeline, so SwiftUI screens share the cache.
public struct ChanRemoteImage: UIViewRepresentable {
    public let url: URL?
    public var scaling: ChanImageView.Scaling
    public var cornerRadius: CGFloat

    public init(url: URL?, scaling: ChanImageView.Scaling = .fit, cornerRadius: CGFloat = 8) {
        self.url = url
        self.scaling = scaling
        self.cornerRadius = cornerRadius
    }

    public func makeUIView(context: Context) -> ChanImageView {
        let view = ChanImageView()
        view.scaling = scaling
        view.cornerRadius = cornerRadius
        return view
    }

    public func updateUIView(_ view: ChanImageView, context: Context) {
        view.scaling = scaling
        view.cornerRadius = cornerRadius
        view.load(url)
    }

    public static func dismantleUIView(_ view: ChanImageView, coordinator: ()) {
        view.reset()
    }
}
