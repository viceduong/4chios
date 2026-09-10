import ChanCore
import Foundation
import GRDB

/// A cached summary of one thread.
///
/// The summary itself is stored as an opaque JSON document so this module never
/// has to know about the AI layer's types.
public struct CachedSummary: Hashable, Sendable {
    public let board: BoardID
    public let op: PostNumber
    public let model: String
    public let createdAt: Date
    /// How many posts the summary covered.
    public let postCount: Int
    public let json: String
}

public extension ChanDatabase {
    func saveSummary(
        board: BoardID,
        op: PostNumber,
        model: String,
        postCount: Int,
        json: String,
        createdAt: Date = Date()
    ) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO thread_summary (board_id, op_no, model, created_at, post_count, json)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(board_id, op_no, model) DO UPDATE SET
                    created_at = excluded.created_at,
                    post_count = excluded.post_count,
                    json = excluded.json
                """,
                arguments: [board.rawValue, op.value, model, createdAt.timeIntervalSince1970, postCount, json]
            )
        }
    }

    func summary(board: BoardID, op: PostNumber, model: String) throws -> CachedSummary? {
        try writer.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT board_id, op_no, model, created_at, post_count, json
                FROM thread_summary
                WHERE board_id = ? AND op_no = ? AND model = ?
                """,
                arguments: [board.rawValue, op.value, model]
            )
            .map { row in
                CachedSummary(
                    board: BoardID(row["board_id"]),
                    op: PostNumber(row["op_no"]),
                    model: row["model"],
                    createdAt: Date(timeIntervalSince1970: row["created_at"]),
                    postCount: row["post_count"],
                    json: row["json"]
                )
            }
        }
    }

    func deleteSummary(board: BoardID, op: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM thread_summary WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
        }
    }
}
