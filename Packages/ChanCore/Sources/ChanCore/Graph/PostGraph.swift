import Foundation

/// The quote relationships inside one thread.
///
/// Built incrementally as posts arrive, so a live thread appends cheaply instead
/// of re-parsing everything. Pure logic — no UI, no storage — which keeps it in
/// the fast CI lane.
public struct PostGraph: Sendable {
    /// post → the posts it quotes, ascending and de-duplicated.
    public private(set) var quotes: [PostNumber: [PostNumber]] = [:]
    /// post → the posts that quote it, ascending.
    public private(set) var backlinks: [PostNumber: [PostNumber]] = [:]
    public private(set) var opNumber: PostNumber?

    private var postsByNumber: [PostNumber: Post] = [:]

    public init() {}

    public mutating func reset(with posts: [Post]) {
        self = PostGraph()
        insert(contentsOf: posts)
    }

    public mutating func insert(contentsOf posts: [Post]) {
        for post in posts { insert(post) }
    }

    public mutating func insert(_ post: Post) {
        postsByNumber[post.no] = post
        if post.isOP { opNumber = post.no }

        let targets = Set(PostHTMLParser.parse(post.commentHTML ?? "").quotedPosts).sorted()

        // A re-inserted post (e.g. an edited OP after a tail refresh) must not
        // leave stale backlinks behind.
        if let previous = quotes[post.no], previous != targets {
            for old in previous {
                backlinks[old]?.removeAll { $0 == post.no }
            }
        }

        quotes[post.no] = targets
        for target in targets where !(backlinks[target] ?? []).contains(post.no) {
            backlinks[target] = ((backlinks[target] ?? []) + [post.no]).sorted()
        }
    }

    public var isEmpty: Bool { postsByNumber.isEmpty }

    public func post(_ number: PostNumber) -> Post? {
        postsByNumber[number]
    }

    public func isOP(_ number: PostNumber) -> Bool {
        number == opNumber
    }

    /// Replies to a post, in posting order.
    public func replies(to number: PostNumber) -> [PostNumber] {
        backlinks[number] ?? []
    }

    public func replyCount(of number: PostNumber) -> Int {
        (backlinks[number] ?? []).count
    }

    /// Posts quoted by a post.
    public func quoted(by number: PostNumber) -> [PostNumber] {
        quotes[number] ?? []
    }

    /// True when the post quotes any post the user wrote.
    public func quotesUser(_ number: PostNumber, myPosts: Set<PostNumber>) -> Bool {
        (quotes[number] ?? []).contains { myPosts.contains($0) }
    }

    /// The label shown next to a `>>` link: `OP`, `You`, or nothing.
    public func annotation(for number: PostNumber, myPosts: Set<PostNumber>) -> String? {
        if isOP(number) { return "OP" }
        if myPosts.contains(number) { return "You" }
        return nil
    }

    /// The parent a post most plausibly replies to: the most recent post it
    /// quotes, falling back to the first quote.
    public func preferredParent(of number: PostNumber) -> PostNumber? {
        let candidates = (quotes[number] ?? []).filter { $0.value < number.value }
        return candidates.max(by: { $0.value < $1.value }) ?? quotes[number]?.first
    }

    /// Root-first conversation chain ending at `number`. Cycle-safe: a post that
    /// quotes a later post (or itself) terminates instead of looping.
    public func chain(to number: PostNumber, limit: Int = 64) -> [PostNumber] {
        var path: [PostNumber] = []
        var seen: Set<PostNumber> = []
        var current: PostNumber? = number

        while let node = current, !seen.contains(node), path.count < limit {
            seen.insert(node)
            path.append(node)
            current = preferredParent(of: node)
        }

        return path.reversed()
    }

    /// Every post reachable by following quotes forward, breadth-first.
    public func descendants(of number: PostNumber, limit: Int = 1000) -> [PostNumber] {
        var result: [PostNumber] = []
        var seen: Set<PostNumber> = [number]
        var queue: [PostNumber] = [number]

        while let node = queue.popLast(), result.count < limit {
            for child in backlinks[node] ?? [] where !seen.contains(child) {
                seen.insert(child)
                result.append(child)
                queue.append(child)
            }
        }

        return result.sorted()
    }

    /// How deep the conversation runs under `number` (0 = leaf).
    public func depth(of number: PostNumber, limit: Int = 32) -> Int {
        var maxDepth = 0
        var seen: Set<PostNumber> = [number]

        func walk(_ node: PostNumber, _ depth: Int) {
            guard depth < limit else { return }
            for child in backlinks[node] ?? [] where !seen.contains(child) {
                seen.insert(child)
                maxDepth = max(maxDepth, depth + 1)
                walk(child, depth + 1)
            }
        }

        walk(number, 0)
        return maxDepth
    }
}
