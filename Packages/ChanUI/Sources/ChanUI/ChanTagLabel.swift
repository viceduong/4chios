import UIKit

/// A small rounded label used for badges (`STICKY`, `NSFW`, `OP`, `WEBM`).
public final class ChanTagLabel: UILabel {
    public var textInsets = UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        font = .systemFont(ofSize: 10, weight: .bold)
        textAlignment = .center
        layer.cornerRadius = 5
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    public override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    public override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}
