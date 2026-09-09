import Foundation
import NukeUI
import SwiftUI
import UIKit

/// A UIKit image view built for reused cells.
///
/// Wraps `NukeUI.LazyImageView` with the app's shared pipeline, a placeholder
/// color, rounded corners, and cancellation on reuse.
public final class ChanImageView: UIView {
    private let imageView = LazyImageView()
    private var currentURL: URL?

    public var cornerRadius: CGFloat = 8 {
        didSet {
            imageView.layer.cornerRadius = cornerRadius
        }
    }

    public var placeholderColor: UIColor = .secondarySystemBackground {
        didSet {
            backgroundColor = placeholderColor
        }
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

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.pipeline = ChanImagePipeline.shared
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = cornerRadius
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Loads a URL, cancelling whatever was in flight.
    public func load(_ url: URL?, transition: LazyImageView.Transition = .fadeIn(duration: 0.2)) {
        guard url != currentURL else { return }
        currentURL = url
        imageView.transition = transition
        imageView.url = url
    }

    /// Clears the view for cell reuse.
    public func reset() {
        currentURL = nil
        imageView.url = nil
    }
}

/// A SwiftUI wrapper around the same pipeline, so SwiftUI screens share the cache.
public struct ChanRemoteImage: UIViewRepresentable {
    public let url: URL?
    public var cornerRadius: CGFloat = 8
    public var contentMode: UIView.ContentMode = .scaleAspectFill

    public init(url: URL?, cornerRadius: CGFloat = 8, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.url = url
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
    }

    public func makeUIView(context: Context) -> ChanImageView {
        let view = ChanImageView()
        view.cornerRadius = cornerRadius
        return view
    }

    public func updateUIView(_ view: ChanImageView, context: Context) {
        view.cornerRadius = cornerRadius
        view.load(url)
    }

    public static func dismantleUIView(_ view: ChanImageView, coordinator: ()) {
        view.reset()
    }
}
