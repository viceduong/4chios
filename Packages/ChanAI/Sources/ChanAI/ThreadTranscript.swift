import ChanCore
import Foundation

/// Renders a thread into a compact, model-readable transcript.
///
/// Pure text work, so it is unit-tested in the fast Linux lane without any
/// network or platform dependency.
public enum ThreadTranscript {
    /// Roughly 9k tokens of transcript per request.
    public static let defaultChunkCharacterLimit = 36_000
    /// A single pathological post cannot dominate a chunk.
    private static let perPostCharacterLimit = 6_000

    public static func render(_ posts: [Post]) -> String {
        posts.map(render).joined(separator: "\n\n")
    }

    public static func render(_ post: Post) -> String {
        var lines: [String] = []

        var header = ">>\(post.no.value)"
        header += " \(post.name ?? "Anonymous")"
        if let trip = post.trip { header += " \(trip)" }
        if let capcode = post.capcode { header += " ##\(capcode)" }
        if post.isOP { header += " [OP]" }
        lines.append(header)

        if let subject = post.subject, !subject.isEmpty {
            lines.append("Subject: \(subject)")
        }

        let body = PostHTMLParser.parse(post.commentHTML ?? "").plainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            lines.append(body)
        }

        if let attachment = post.attachment {
            var media = "[file: \(attachment.filename)\(attachment.ext) \(attachment.width)x\(attachment.height) \(attachment.size) bytes"
            if attachment.isSpoiler { media += " spoiler" }
            if attachment.isVideo { media += " video" }
            if attachment.isAnimated { media += " animated" }
            media += "]"
            lines.append(media)
        }

        var rendered = lines.joined(separator: "\n")
        if rendered.count > perPostCharacterLimit {
            rendered = String(rendered.prefix(perPostCharacterLimit)) + "\n[truncated]"
        }
        return rendered
    }

    /// A budgeted view of the thread: the OP, then as much of the tail as fits.
    ///
    /// Follow-up questions are almost always about what was just said, so the
    /// tail is kept and the omission is stated rather than quietly dropped.
    public static func context(_ posts: [Post], characterLimit: Int) -> String {
        let full = render(posts)
        guard full.count > characterLimit, let first = posts.first else { return full }

        var tail: [Post] = []
        var size = render(first).count

        for post in posts.dropFirst().reversed() {
            let length = render(post).count + 2
            if size + length > characterLimit { break }
            tail.insert(post, at: 0)
            size += length
        }

        let omitted = posts.count - 1 - tail.count
        let marker = omitted > 0 ? "\n\n[\(omitted) earlier posts omitted]\n\n" : "\n\n"
        return render(first) + marker + render(tail)
    }

    /// Splits a thread into chunks that each fit a request.
    public static func chunks(
        _ posts: [Post],
        characterLimit: Int = defaultChunkCharacterLimit
    ) -> [[Post]] {
        guard !posts.isEmpty else { return [] }

        var result: [[Post]] = []
        var current: [Post] = []
        var size = 0

        for post in posts {
            let length = render(post).count + 2
            if !current.isEmpty, size + length > characterLimit {
                result.append(current)
                current = []
                size = 0
            }
            current.append(post)
            size += length
        }

        if !current.isEmpty { result.append(current) }
        return result
    }
}
