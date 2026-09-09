import ChanCore
import Foundation

/// Media URLs, including the mid-size variant 4chan generates when `m_img == 1`.
///
/// Loading order is always thumbnail → preview → full, so the UI can show something
/// instantly on slow connections.
public enum ChanMediaURL {
    /// 250 px (OP) / 125 px (reply) thumbnail. 4chan always serves these as JPEG.
    public static func thumbnail(board: BoardID, tim: Int) -> URL {
        url(host: .media, path: "/\(board.rawValue)/\(tim)s.jpg")
    }

    /// Up to 1024 px JPEG preview, only available when the post has `m_img == 1`.
    public static func preview(board: BoardID, tim: Int) -> URL {
        url(host: .media, path: "/\(board.rawValue)/\(tim)m.jpg")
    }

    /// The original file, exactly as uploaded.
    public static func full(board: BoardID, tim: Int, ext: String) -> URL {
        let normalized = ext.hasPrefix(".") ? ext : ".\(ext)"
        return url(host: .media, path: "/\(board.rawValue)/\(tim)\(normalized)")
    }

    /// Default spoiler image, used when `custom_spoiler == 0`.
    public static func spoilerImage(board: BoardID) -> URL {
        url(host: .staticContent, path: "/image/spoiler-\(board.rawValue).png")
    }

    /// One of the board's custom spoiler images, chosen by `custom_spoiler` (1...8).
    public static func customSpoilerImage(board: BoardID, index: Int) -> URL {
        url(host: .staticContent, path: "/image/spoiler-\(board.rawValue)\(index).png")
    }

    private static func url(host: ChanHost, path: String) -> URL {
        URL(string: path, relativeTo: host.url)!.absoluteURL
    }
}
