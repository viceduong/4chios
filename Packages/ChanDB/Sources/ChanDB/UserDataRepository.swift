import ChanCore
import Foundation
import GRDB

/// A saved thread.
public struct Bookmark: Hashable, Sendable, Identifiable {
    public var id: String { "\(board.rawValue)/\(op.value)" }
    public let board: BoardID
    public let op: PostNumber
    public let addedAt: Date
    public let note: String?
}

/// A thread being watched for new replies.
public struct WatchedThread: Hashable, Sendable, Identifiable {
    public var id: String { "\(board.rawValue)/\(op.value)" }
    public let board: BoardID
    public let op: PostNumber
    public let addedAt: Date
    public let lastSeenReply: Int
    public let notify: Bool
}

public extension ChanDatabase {
    // MARK: - Bookmarks

    func addBookmark(board: BoardID, op: PostNumber, note: String? = nil, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO bookmark (board_id, op_no, added_at, note) VALUES (?, ?, ?, ?)
                ON CONFLICT(board_id, op_no) DO UPDATE SET note = excluded.note
                """,
                arguments: [board.rawValue, op.value, date.timeIntervalSince1970, note]
            )
        }
    }

    func removeBookmark(board: BoardID, op: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM bookmark WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
        }
    }

    func isBookmarked(board: BoardID, op: PostNumber) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM bookmark WHERE board_id = ? AND op_no = ?)",
                arguments: [board.rawValue, op.value]
            ) ?? false
        }
    }

    func bookmarks() throws -> [Bookmark] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT board_id, op_no, added_at, note FROM bookmark ORDER BY added_at DESC")
                .map { row in
                    Bookmark(
                        board: BoardID(row["board_id"]),
                        op: PostNumber(row["op_no"]),
                        addedAt: Date(timeIntervalSince1970: row["added_at"]),
                        note: row["note"]
                    )
                }
        }
    }

    // MARK: - Watchlist

    func addWatch(board: BoardID, op: PostNumber, notify: Bool = true, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO watch (board_id, op_no, added_at, last_seen_reply, notify) VALUES (?, ?, ?, 0, ?)
                ON CONFLICT(board_id, op_no) DO UPDATE SET notify = excluded.notify
                """,
                arguments: [board.rawValue, op.value, date.timeIntervalSince1970, notify]
            )
        }
    }

    func removeWatch(board: BoardID, op: PostNumber) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM watch WHERE board_id = ? AND op_no = ?", arguments: [board.rawValue, op.value])
        }
    }

    func isWatched(board: BoardID, op: PostNumber) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM watch WHERE board_id = ? AND op_no = ?)",
                arguments: [board.rawValue, op.value]
            ) ?? false
        }
    }

    func watchedThreads() throws -> [WatchedThread] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT board_id, op_no, added_at, last_seen_reply, notify FROM watch ORDER BY added_at DESC"
            )
            .map { row in
                WatchedThread(
                    board: BoardID(row["board_id"]),
                    op: PostNumber(row["op_no"]),
                    addedAt: Date(timeIntervalSince1970: row["added_at"]),
                    lastSeenReply: row["last_seen_reply"],
                    notify: row["notify"]
                )
            }
        }
    }

    func updateWatchProgress(board: BoardID, op: PostNumber, replies: Int) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE watch SET last_seen_reply = ? WHERE board_id = ? AND op_no = ?",
                arguments: [replies, board.rawValue, op.value]
            )
        }
    }

    // MARK: - Read state

    func setLastRead(board: BoardID, op: PostNumber, postNumber: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO read_state (board_id, op_no, last_read_no) VALUES (?, ?, ?)
                ON CONFLICT(board_id, op_no) DO UPDATE SET last_read_no = excluded.last_read_no
                """,
                arguments: [board.rawValue, op.value, postNumber.value]
            )
        }
    }

    func lastRead(board: BoardID, op: PostNumber) throws -> PostNumber? {
        try writer.read { db -> PostNumber? in
            let value = try Int.fetchOne(
                db,
                sql: "SELECT last_read_no FROM read_state WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
            return value.map { PostNumber($0) }
        }
    }

    // MARK: - Posts written by the user

    /// Records a successfully submitted post so replies to it can be marked `(You)`.
    func recordMyPost(board: BoardID, number: PostNumber, thread: PostNumber, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO my_post (board_id, no, thread_no, created_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(board_id, no) DO NOTHING
                """,
                arguments: [board.rawValue, number.value, thread.value, date.timeIntervalSince1970]
            )
        }
    }

    /// Lets the user tag an existing post as theirs (4chan-X's "mark as yours").
    func markAsMine(board: BoardID, number: PostNumber, thread: PostNumber, at date: Date = Date()) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO my_post (board_id, no, thread_no, created_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(board_id, no) DO UPDATE SET thread_no = excluded.thread_no
                """,
                arguments: [board.rawValue, number.value, thread.value, date.timeIntervalSince1970]
            )
        }
    }

    func removeMyPost(board: BoardID, number: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM my_post WHERE board_id = ? AND no = ?",
                arguments: [board.rawValue, number.value]
            )
        }
    }

    func myPostNumbers(board: BoardID) throws -> Set<PostNumber> {
        try writer.read { db -> Set<PostNumber> in
            let numbers = try Int64.fetchAll(
                db,
                sql: "SELECT no FROM my_post WHERE board_id = ?",
                arguments: [board.rawValue]
            )
            return Set(numbers.map { PostNumber(Int($0)) })
        }
    }

    func isMyPost(board: BoardID, number: PostNumber) throws -> Bool {
        try writer.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM my_post WHERE board_id = ? AND no = ?)",
                arguments: [board.rawValue, number.value]
            ) ?? false
        }
    }

    // MARK: - Filters
    @discardableResult
    func saveFilter(_ filter: ChanFilter) throws -> ChanFilter {
        try writer.write { db in
            if filter.id == 0 {
                try db.execute(
                    sql: """
                    INSERT INTO filter (board_id, kind, pattern, action, enabled, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        filter.board?.rawValue, filter.kind.rawValue, filter.pattern,
                        filter.action.rawValue, filter.enabled, filter.createdAt.timeIntervalSince1970,
                    ]
                )
                return ChanFilter(
                    id: db.lastInsertedRowID,
                    board: filter.board,
                    kind: filter.kind,
                    pattern: filter.pattern,
                    action: filter.action,
                    enabled: filter.enabled,
                    createdAt: filter.createdAt
                )
            }
            try db.execute(
                sql: "UPDATE filter SET board_id = ?, kind = ?, pattern = ?, action = ?, enabled = ? WHERE id = ?",
                arguments: [
                    filter.board?.rawValue, filter.kind.rawValue, filter.pattern,
                    filter.action.rawValue, filter.enabled, filter.id,
                ]
            )
            return filter
        }
    }

    func deleteFilter(id: Int64) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM filter WHERE id = ?", arguments: [id])
        }
    }

    func filters() throws -> [ChanFilter] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT id, board_id, kind, pattern, action, enabled, created_at FROM filter ORDER BY created_at"
            )
            .compactMap { row in
                let boardID: String? = row["board_id"]
                guard let kind = ChanFilterKind(rawValue: row["kind"]),
                      let action = ChanFilterAction(rawValue: row["action"]) else { return nil }
                return ChanFilter(
                    id: row["id"],
                    board: boardID.map { BoardID($0) },
                    kind: kind,
                    pattern: row["pattern"],
                    action: action,
                    enabled: row["enabled"],
                    createdAt: Date(timeIntervalSince1970: row["created_at"])
                )
            }
        }
    }
}
