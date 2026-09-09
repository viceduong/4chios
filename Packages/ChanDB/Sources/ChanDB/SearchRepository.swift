import ChanCore
import Foundation
import GRDB

/// A post found by full-text search, with the board it came from.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public var id: String { "\(board.rawValue)/\(post.no.value)" }
    public let board: BoardID
    public let post: Post
}

public extension ChanDatabase {
    /// Full-text search over every cached post body (FTS5).
    ///
    /// The query is tokenized and each token is turned into a prefix match, so
    /// "hel wor" finds "hello world" without the user needing FTS syntax.
    func search(_ query: String, limit: Int = 50) throws -> [SearchHit] {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }

        guard !tokens.isEmpty else { return [] }
        let match = tokens.joined(separator: " AND ")

        return try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT f.board_id AS board_id, p.json AS json
                FROM post_fts f
                JOIN post p ON p.board_id = f.board_id AND p.no = f.no
                WHERE post_fts MATCH ?
                ORDER BY f.rank
                LIMIT ?
                """,
                arguments: [match, limit]
            )
            .compactMap { row in
                let json: String = row["json"]
                guard let post = try? Self.decode(Post.self, from: json) else { return nil }
                return SearchHit(board: BoardID(row["board_id"]), post: post)
            }
        }
    }

    /// Number of indexed posts, useful for a "search index" settings row.
    func indexedPostCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM post_fts") ?? 0
        }
    }

    /// Rebuilds the search index from the post table.
    func rebuildSearchIndex() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM post_fts")
            let rows = try Row.fetchAll(db, sql: "SELECT board_id, op_no, no, json FROM post")
            for row in rows {
                let json: String = row["json"]
                guard let post = try? Self.decode(Post.self, from: json) else { continue }
                let plain = PostHTMLParser.parse(post.commentHTML ?? "").plainText
                guard !plain.isEmpty else { continue }
                try db.execute(
                    sql: "INSERT INTO post_fts (com_plain, board_id, op_no, no) VALUES (?, ?, ?, ?)",
                    arguments: [plain, row["board_id"] as String, row["op_no"] as Int, row["no"] as Int]
                )
            }
        }
    }
}
