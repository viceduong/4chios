import Foundation

/// Text matching for the catalog filter and find-in-thread.
///
/// One place decides what a post is searchable by, so the catalog and the
/// thread cannot drift apart on what "matches" means.
public enum PostSearch {
    /// Case- and diacritic-folded form, applied to both the haystack and the
    /// query so "cafe" finds "Café". Lowercasing alone would not.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The text a post is matched against: subject, body, and filename. Cached by
    /// callers that search repeatedly, because parsing the body is the expensive
    /// part.
    public static func haystack(for post: Post) -> String {
        var parts: [String] = []
        if let subject = post.subject, !subject.isEmpty {
            parts.append(subject)
        }
        parts.append(PostHTMLParser.parse(post.commentHTML ?? "").plainText)
        if let filename = post.attachment?.filename {
            parts.append(filename)
        }
        return normalized(parts.joined(separator: "\n"))
    }

    /// True when the query appears in the post, ignoring case and diacritics.
    public static func matches(_ post: Post, query: String) -> Bool {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return false }
        return haystack(for: post).contains(needle)
    }

    /// Post numbers that match, in the order given.
    public static func matches(in posts: [Post], query: String) -> [PostNumber] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        return posts.filter { haystack(for: $0).contains(needle) }.map(\.no)
    }
}
