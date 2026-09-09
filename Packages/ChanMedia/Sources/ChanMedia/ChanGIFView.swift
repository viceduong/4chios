import Foundation
import Gifu
import SwiftUI
import UIKit

/// An animated GIF view backed by Gifu.
///
/// NukeUI's `LazyImageView` renders only the first frame of an animated GIF, so
/// animated attachments get this dedicated view instead.
public final class ChanGIFView: UIView {
    private let gifView = GIFImageView()
    private var currentURL: URL?

    public var contentMode: UIView.ContentMode = .scaleAspectFit {
        didSet { gifView.contentMode = contentMode }
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
        gifView.translatesAutoresizingMaskIntoConstraints = false
        gifView.contentMode = contentMode
        addSubview(gifView)
        NSLayoutConstraint.activate([
            gifView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gifView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gifView.topAnchor.constraint(equalTo: topAnchor),
            gifView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    public func load(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        gifView.prepareForReuse()
        guard let url else { return }
        gifView.animate(withGIFURL: url)
    }

    public func reset() {
        currentURL = nil
        gifView.prepareForReuse()
    }
}

/// SwiftUI wrapper for `ChanGIFView`.
public struct ChanGIFImage: UIViewRepresentable {
    public let url: URL?
    public var contentMode: UIView.ContentMode = .scaleAspectFit

    public init(url: URL?, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.url = url
        self.contentMode = contentMode
    }

    public func makeUIView(context: Context) -> ChanGIFView {
        let view = ChanGIFView()
        view.contentMode = contentMode
        return view
    }

    public func updateUIView(_ view: ChanGIFView, context: Context) {
        view.contentMode = contentMode
        view.load(url)
    }

    public static func dismantleUIView(_ view: ChanGIFView, coordinator: ()) {
        view.reset()
    }
}
