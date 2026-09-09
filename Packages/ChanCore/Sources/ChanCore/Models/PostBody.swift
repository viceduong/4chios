import Foundation

/// A styled, platform-agnostic run of post text.
///
/// The HTML parser produces these; each platform layer converts them into its own
/// attributed-string representation. Keeping the intermediate form free of UIKit
/// is what lets the parser (the most bug-prone code in the app) be unit-tested on
/// Linux in the fast CI lane.
public struct PostRun: Hashable, Sendable {
    public var text: String
    public var style: PostStyle
    public var link: PostLink?

    public init(text: String, style: PostStyle = [], link: PostLink? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }
}

/// Visual/interaction flags that can combine on a single run.
public struct PostStyle: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = PostStyle(rawValue: 1 << 0)
    public static let italic = PostStyle(rawValue: 1 << 1)
    public static let underline = PostStyle(rawValue: 1 << 2)
    /// `<s>` — hidden until tapped.
    public static let spoiler = PostStyle(rawValue: 1 << 3)
    /// `<span class="quote">` — greentext.
    public static let quote = PostStyle(rawValue: 1 << 4)
    /// `<pre class="prettyprint">` — monospaced.
    public static let code = PostStyle(rawValue: 1 << 5)
    /// `<span class="sjis">` — Shift-JIS text.
    public static let sjis = PostStyle(rawValue: 1 << 6)
    /// `<a class="deadlink">` — link to a deleted post.
    public static let deadLink = PostStyle(rawValue: 1 << 7)
}

/// Where a run points, if anywhere.
public enum PostLink: Hashable, Sendable {
    /// `>>123` — scroll to and flash the referenced post.
    case quote(PostNumber)
    /// An external URL.
    case external(URL)
    /// `>>123` to a post that no longer exists.
    case dead(PostNumber)

    /// Custom scheme used to route quote taps through `OpenURLAction` in SwiftUI.
    public static let scheme = "ch4ios"

    public var url: URL? {
        switch self {
        case let .quote(number):
            return URL(string: "\(Self.scheme)://post/\(number.value)")
        case let .external(url):
            return url
        case let .dead(number):
            return URL(string: "\(Self.scheme)://dead/\(number.value)")
        }
    }

    /// Parses a `ch4ios://post/123` style URL produced by `url`.
    public static func from(url: URL) -> PostLink? {
        guard url.scheme == scheme, let host = url.host else { return nil }
        let number = PostNumber(Int(url.lastPathComponent) ?? 0)
        switch host {
        case "post": return .quote(number)
        case "dead": return .dead(number)
        default: return nil
        }
    }
}

/// A parsed post body.
public struct PostBody: Hashable, Sendable {
    public let runs: [PostRun]

    public init(runs: [PostRun]) {
        self.runs = runs
    }

    public var plainText: String {
        runs.map(\.text).joined()
    }

    public var isEmpty: Bool {
        runs.allSatisfy { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Post numbers referenced by `>>` links, in order of appearance.
    public var quotedPosts: [PostNumber] {
        runs.compactMap { run in
            if case let .quote(number)? = run.link { return number }
            return nil
        }
    }
}
