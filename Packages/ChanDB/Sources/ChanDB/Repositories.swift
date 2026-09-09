import ChanCore
import Foundation
import GRDB

// MARK: - Boards

public extension ChanDatabase {
    /// Upserts the board list fetched from `/boards.json`.
    func save(_ boards: [Board]) throws {
        try writer.write { db in
            for board in boards {
                let json = try Self.encode(board)
                try db.execute(
                    sql: """
                    INSERT INTO board (id, title, ws_board, json)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        ws_board = excluded.ws_board,
                        json = excluded.json
                    """,
                    arguments: [board.board.rawValue, board.title, board.isWorkSafe, json]
                )
            }
        }
    }

    func boards() throws -> [Board] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT json FROM board ORDER BY title COLLATE NOCASE")
                .compactMap { row in
                    let json: String = row["json"]
                    return try? Self.decode(Board.self, from: json)
                }
        }
    }

    func board(_ id: BoardID) throws -> Board? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT json FROM board WHERE id = ?", arguments: [id.rawValue]
            ) else { return nil }
            let json: String = row["json"]
            return try? Self.decode(Board.self, from: json)
        }
    }

    func boardCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM board") ?? 0 }
    }
}

// MARK: - Threads and posts

public extension ChanDatabase {
    /// Replaces a board's catalog: upserts every OP and its thread row.
    func saveCatalog(board: BoardID, posts: [Post], seenAt: Date = Date()) throws {
        try writer.write { db in
            for post in posts {
                try Self.upsert(post: post, board: board, in: db)
                if post.isOP {
                    try Self.upsertThreadRow(post, board: board, seenAt: seenAt, in: db)
                }
            }
        }
    }

    /// OP posts for a board, sticky first, most recently bumped next.
    func catalog(board: BoardID) throws -> [Post] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT json FROM thread
                WHERE board_id = ?
                ORDER BY sticky DESC, last_modified DESC
                """,
                arguments: [board.rawValue]
            )
            .compactMap { row in
                let json: String = row["json"]
                return try? Self.decode(Post.self, from: json)
            }
        }
    }

    /// Replaces a whole thread (full fetch).
    func saveThread(board: BoardID, op: PostNumber, posts: [Post], seenAt: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM post WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
            for post in posts {
                try Self.upsert(post: post, board: board, in: db)
            }
            if let opPost = posts.first(where: { $0.isOP }) {
                try Self.upsertThreadRow(opPost, board: board, seenAt: seenAt, in: db)
            }
        }
    }

    /// Appends incremental posts from a tail poll.
    func appendTail(board: BoardID, op: PostNumber, posts: [Post]) throws {
        try writer.write { db in
            for post in posts {
                try Self.upsert(post: post, board: board, in: db)
            }
            if let opPost = posts.first(where: { $0.isOP }) {
                try Self.upsertThreadRow(opPost, board: board, seenAt: Date(), in: db)
            }
        }
    }

    /// Every cached post of a thread, oldest first.
    func posts(board: BoardID, op: PostNumber) throws -> [Post] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT json FROM post WHERE board_id = ? AND op_no = ? ORDER BY no",
                arguments: [board.rawValue, op.value]
            )
            .compactMap { row in
                let json: String = row["json"]
                return try? Self.decode(Post.self, from: json)
            }
        }
    }

    /// The highest post number cached for a thread, or nil.
    func lastPostNumber(board: BoardID, op: PostNumber) throws -> PostNumber? {
        try writer.read { db in
            let value = try Int.fetchOne(
                db,
                sql: "SELECT MAX(no) FROM post WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
            return value.map(PostNumber.init)
        }
    }

    /// Thread metadata used by the watchlist and notifications.
    func threadMetadata(board: BoardID, op: PostNumber) throws -> CachedThread? {
        try writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT board_id, op_no, last_modified, replies, images, sticky, closed, archived, seen_at
                FROM thread WHERE board_id = ? AND op_no = ?
                """,
                arguments: [board.rawValue, op.value]
            ) else { return nil }

            let lastModified: Double? = row["last_modified"]
            return CachedThread(
                board: BoardID(row["board_id"]),
                op: PostNumber(row["op_no"]),
                lastModified: lastModified.map { Date(timeIntervalSince1970: $0) },
                replies: row["replies"],
                images: row["images"],
                isSticky: row["sticky"],
                isClosed: row["closed"],
                isArchived: row["archived"],
                seenAt: Date(timeIntervalSince1970: row["seen_at"])
            )
        }
    }

    /// Removes cached posts for threads that no longer exist on the board.
    func pruneThreads(board: BoardID, keeping opNumbers: Set<PostNumber>) throws {
        try writer.write { db in
            let existing = try Int64.fetchAll(
                db, sql: "SELECT op_no FROM thread WHERE board_id = ?", arguments: [board.rawValue]
            )
            let stale = existing.map { PostNumber(Int($0)) }.filter { !opNumbers.contains($0) }
            for op in stale {
                try db.execute(sql: "DELETE FROM thread WHERE board_id = ? AND op_no = ?", arguments: [board.rawValue, op.value])
                try db.execute(sql: "DELETE FROM post WHERE board_id = ? AND op_no = ?", arguments: [board.rawValue, op.value])
            }
        }
    }

    // MARK: Private helpers

    private static func upsert(post: Post, board: BoardID, in db: Database) throws {
        let json = try encode(post)
        let opNumber = post.isOP ? post.no.value : post.resto.value

        try db.execute(
            sql: """
            INSERT INTO post (board_id, op_no, no, time, is_op, json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(board_id, no) DO UPDATE SET
                op_no = excluded.op_no,
                time = excluded.time,
                is_op = excluded.is_op,
                json = excluded.json
            """,
            arguments: [
                board.rawValue, opNumber, post.no.value,
                post.time.timeIntervalSince1970, post.isOP, json,
            ]
        )

        let plain = PostHTMLParser.parse(post.commentHTML ?? "").plainText
        guard !plain.isEmpty else { return }

        try db.execute(
            sql: "DELETE FROM post_fts WHERE board_id = ? AND no = ?",
            arguments: [board.rawValue, post.no.value]
        )
        try db.execute(
            sql: "INSERT INTO post_fts (com_plain, board_id, op_no, no) VALUES (?, ?, ?, ?)",
            arguments: [plain, board.rawValue, opNumber, post.no.value]
        )
    }

    private static func upsertThreadRow(_ post: Post, board: BoardID, seenAt: Date, in db: Database) throws {
        let json = try encode(post)
        try db.execute(
            sql: """
            INSERT INTO thread (board_id, op_no, time, last_modified, replies, images, sticky, closed, archived, seen_at, json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(board_id, op_no) DO UPDATE SET
                time = excluded.time,
                last_modified = excluded.last_modified,
                replies = excluded.replies,
                images = excluded.images,
                sticky = excluded.sticky,
                closed = excluded.closed,
                archived = excluded.archived,
                seen_at = excluded.seen_at,
                json = excluded.json
            """,
            arguments: [
                board.rawValue, post.no.value, post.time.timeIntervalSince1970,
                (post.lastModified ?? post.time).timeIntervalSince1970,
                post.replies ?? 0, post.images ?? 0,
                post.isSticky ?? false, post.isClosed ?? false, post.isArchived ?? false,
                seenAt.timeIntervalSince1970, json,
            ]
        )
    }
}

/// Lightweight thread row, used by the watchlist.
public struct CachedThread: Hashable, Sendable {
    public let board: BoardID
    public let op: PostNumber
    public let lastModified: Date?
    public let replies: Int?
    public let images: Int?
    public let isSticky: Bool
    public let isClosed: Bool
    public let isArchived: Bool
    public let seenAt: Date
}

// MARK: - Meta key/value

public extension ChanDatabase {
    func setMeta(_ value: String, forKey key: String) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO meta (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [key, value]
            )
        }
    }

    func meta(forKey key: String) throws -> String? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = ?", arguments: [key])
        }
    }

    func lastCatalogSync(board: BoardID) throws -> Date? {
        try meta(forKey: "catalog.\(board.rawValue).synced").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
    }

    func markCatalogSynced(board: BoardID, at date: Date = Date()) throws {
        try setMeta(String(date.timeIntervalSince1970), forKey: "catalog.\(board.rawValue).synced")
    }
}
