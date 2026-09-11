import ChanCore
import Foundation
import GRDB

/// A single post the reader bookmarked, for reading again later.
public struct PostBookmark: Hashable, Sendable {
    public let board: BoardID
    public let postNumber: PostNumber
    public let threadNumber: PostNumber
    public let addedAt: Date
    /// The post as it looked when it was bookmarked.
    ///
    /// Stored rather than looked up, because a saved post has to outlive the
    /// thread cache: resolving it from live storage would leave the reader with
    /// nothing precisely when the saved copy matters most.
    public let post: Post?

    public init(
        board: BoardID,
        postNumber: PostNumber,
        threadNumber: PostNumber,
        addedAt: Date,
        post: Post?
    ) {
        self.board = board
        self.postNumber = postNumber
        self.threadNumber = threadNumber
        self.addedAt = addedAt
        self.post = post
    }
}

public extension ChanDatabase {
    // MARK: - Post bookmarks

    func addPostBookmark(
        board: BoardID,
        postNumber: PostNumber,
        threadNumber: PostNumber,
        snapshot: Post? = nil,
        at date: Date = Date()
    ) throws {
        let json = snapshot.flatMap { try? Self.encode($0) }
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO post_bookmark (board_id, post_no, op_no, added_at, json)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(board_id, post_no) DO UPDATE SET
                    op_no = excluded.op_no,
                    -- Never overwrite a stored snapshot with nothing.
                    json = COALESCE(excluded.json, post_bookmark.json)
                """,
                arguments: [board.rawValue, postNumber.value, threadNumber.value,
                            date.timeIntervalSince1970, json]
            )
        }
    }

    func removePostBookmark(board: BoardID, postNumber: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM post_bookmark WHERE board_id = ? AND post_no = ?",
                arguments: [board.rawValue, postNumber.value]
            )
        }
    }

    func isPostBookmarked(board: BoardID, postNumber: PostNumber) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM post_bookmark WHERE board_id = ? AND post_no = ?)",
                arguments: [board.rawValue, postNumber.value]
            ) ?? false
        }
    }

    func postBookmarks(board: BoardID? = nil) throws -> [PostBookmark] {
        try writer.read { db in
            let rows: [Row]
            if let board {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT board_id, post_no, op_no, added_at, json FROM post_bookmark
                    WHERE board_id = ? ORDER BY added_at DESC
                    """,
                    arguments: [board.rawValue]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT board_id, post_no, op_no, added_at, json FROM post_bookmark
                    ORDER BY added_at DESC
                    """
                )
            }
            return rows.map { row in
                let json: String? = row["json"]
                return PostBookmark(
                    board: BoardID(row["board_id"]),
                    postNumber: PostNumber(row["post_no"]),
                    threadNumber: PostNumber(row["op_no"]),
                    addedAt: Date(timeIntervalSince1970: row["added_at"]),
                    post: json.flatMap { try? Self.decode(Post.self, from: $0) }
                )
            }
        }
    }

    func postBookmarkCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM post_bookmark") ?? 0 }
    }

    // MARK: - Bookmarked media

    /// Marks a downloaded file as explicitly bookmarked.
    func bookmarkMedia(
        board: BoardID,
        tim: Int,
        ext: String,
        postNumber: PostNumber,
        threadNumber: PostNumber,
        filename: String,
        byteCount: Int,
        at date: Date = Date()
    ) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO saved_media
                    (board_id, tim, ext, post_no, op_no, filename, byte_count, saved_at, bookmarked_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(board_id, tim) DO UPDATE SET
                    ext = excluded.ext,
                    post_no = excluded.post_no,
                    op_no = excluded.op_no,
                    filename = excluded.filename,
                    byte_count = excluded.byte_count,
                    bookmarked_at = excluded.bookmarked_at
                """,
                arguments: [
                    board.rawValue, tim, ext, postNumber.value, threadNumber.value,
                    filename, byteCount, date.timeIntervalSince1970, date.timeIntervalSince1970,
                ]
            )
        }
    }

    /// Clears the bookmark marker. The file is removed by the caller.
    func unbookmarkMedia(board: BoardID, tim: Int) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE saved_media SET bookmarked_at = NULL WHERE board_id = ? AND tim = ?",
                arguments: [board.rawValue, tim]
            )
        }
    }

    func bookmarkedMedia() throws -> [SavedMediaRecord] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT board_id, tim, ext, post_no, op_no, filename, byte_count, saved_at, bookmarked_at
                FROM saved_media WHERE bookmarked_at IS NOT NULL ORDER BY bookmarked_at DESC
                """
            )
            .map(Self.mediaRecord(from:))
        }
    }

    func bookmarkedMediaCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM saved_media WHERE bookmarked_at IS NOT NULL") ?? 0
        }
    }

    /// Removes the bookmarked row outright, used when the file is deleted.
    func deleteMediaRecord(board: BoardID, tim: Int) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM saved_media WHERE board_id = ? AND tim = ?",
                arguments: [board.rawValue, tim]
            )
        }
    }
}
