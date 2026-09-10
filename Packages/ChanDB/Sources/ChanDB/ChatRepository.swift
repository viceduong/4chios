import ChanCore
import Foundation
import GRDB

/// A saved conversation about one thread.
///
/// The turns are stored as an opaque JSON document, so this module never has to
/// know about the AI layer's types.
public struct CachedChat: Hashable, Sendable {
    public let board: BoardID
    public let op: PostNumber
    public let updatedAt: Date
    public let json: String
}

public extension ChanDatabase {
    func saveChat(
        board: BoardID,
        op: PostNumber,
        json: String,
        updatedAt: Date = Date()
    ) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO thread_chat (board_id, op_no, updated_at, json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(board_id, op_no) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    json = excluded.json
                """,
                arguments: [board.rawValue, op.value, updatedAt.timeIntervalSince1970, json]
            )
        }
    }

    func chat(board: BoardID, op: PostNumber) throws -> CachedChat? {
        try writer.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT board_id, op_no, updated_at, json
                FROM thread_chat
                WHERE board_id = ? AND op_no = ?
                """,
                arguments: [board.rawValue, op.value]
            )
            .map { row in
                CachedChat(
                    board: BoardID(row["board_id"]),
                    op: PostNumber(row["op_no"]),
                    updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
                    json: row["json"]
                )
            }
        }
    }

    func deleteChat(board: BoardID, op: PostNumber) throws {
        try writer.write { db in
            try db.execute(
                sql: "DELETE FROM thread_chat WHERE board_id = ? AND op_no = ?",
                arguments: [board.rawValue, op.value]
            )
        }
    }
}
