import Foundation

/// Text matching for the catalog filter and find-in-thread.
///
/// One place decides what a post is searchable by, so the catalog and the
/// thread cannot drift apart on what "matches" means.
public enum PostSearch {
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
        return parts.joined(separator: "\n").lowercased()
    }

    /// True when the query appears in the post, ignoring case and diacritics.
    public static func matches(_ post: Post, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return haystack(for: post).range(of: trimmed.lowercased()) != nil
    }

    /// Post numbers that match, in the order given.
    public static func matches(in posts: [Post], query: String) -> [PostNumber] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return posts.filter { haystack(for: $0).contains(trimmed) }.map(\.no)
    }
}
