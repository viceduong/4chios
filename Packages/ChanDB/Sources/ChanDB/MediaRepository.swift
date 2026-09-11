import ChanCore
import Foundation
import GRDB

/// A media file that has been downloaded to the device.
public struct SavedMediaRecord: Hashable, Sendable {
    public let board: BoardID
    public let tim: Int
    public let ext: String
    public let postNumber: PostNumber
    public let filename: String
    public let byteCount: Int
    public let savedAt: Date

    public init(
        board: BoardID,
        tim: Int,
        ext: String,
        postNumber: PostNumber,
        filename: String,
        byteCount: Int,
        savedAt: Date
    ) {
        self.board = board
        self.tim = tim
        self.ext = ext
        self.postNumber = postNumber
        self.filename = filename
        self.byteCount = byteCount
        self.savedAt = savedAt
    }

    public var fileName: String {
        "\(tim)\(ext.hasPrefix(".") ? ext : ".\(ext)")"
    }
}

public extension ChanDatabase {
    /// Records a file that now exists on disk.
    func saveMediaRecord(_ record: SavedMediaRecord) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO saved_media (board_id, tim, ext, post_no, filename, byte_count, saved_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(board_id, tim) DO UPDATE SET
                    ext = excluded.ext,
                    post_no = excluded.post_no,
                    filename = excluded.filename,
                    byte_count = excluded.byte_count,
                    saved_at = excluded.saved_at
                """,
                arguments: [
                    record.board.rawValue, record.tim, record.ext, record.postNumber.value,
                    record.filename, record.byteCount, record.savedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    func savedMedia(board: BoardID) throws -> [SavedMediaRecord] {
        try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT board_id, tim, ext, post_no, filename, byte_count, saved_at
                FROM saved_media WHERE board_id = ? ORDER BY post_no, tim
                """,
                arguments: [board.rawValue]
            )
            .map(Self.mediaRecord(from:))
        }
    }

    /// The `tim` values already on disk, so a download can skip them.
    func savedMediaTimestamps(board: BoardID) throws -> Set<Int> {
        try writer.read { db in
            let values = try Int64.fetchAll(
                db,
                sql: "SELECT tim FROM saved_media WHERE board_id = ?",
                arguments: [board.rawValue]
            )
            return Set(values.map(Int.init))
        }
    }

    /// Bytes on disk, for the whole device or one board.
    func savedMediaByteCount(board: BoardID? = nil) throws -> Int {
        try writer.read { db in
            let sql: String
            let arguments: StatementArguments
            if let board {
                sql = "SELECT COALESCE(SUM(byte_count), 0) FROM saved_media WHERE board_id = ?"
                arguments = [board.rawValue]
            } else {
                sql = "SELECT COALESCE(SUM(byte_count), 0) FROM saved_media"
                arguments = []
            }
            return try Int.fetchOne(db, sql: sql, arguments: arguments) ?? 0
        }
    }

    func mediaRecordCount(board: BoardID? = nil) throws -> Int {
        try writer.read { db in
            if let board {
                return try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM saved_media WHERE board_id = ?",
                    arguments: [board.rawValue]
                ) ?? 0
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM saved_media") ?? 0
        }
    }

    func deleteMediaRecords(board: BoardID, tims: [Int]) throws {
        guard !tims.isEmpty else { return }
        try writer.write { db in
            for tim in tims {
                try db.execute(
                    sql: "DELETE FROM saved_media WHERE board_id = ? AND tim = ?",
                    arguments: [board.rawValue, tim]
                )
            }
        }
    }

    func deleteAllMediaRecords() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM saved_media")
        }
    }

    private static func mediaRecord(from row: Row) -> SavedMediaRecord {
        SavedMediaRecord(
            board: BoardID(row["board_id"]),
            tim: row["tim"],
            ext: row["ext"],
            postNumber: PostNumber(row["post_no"]),
            filename: row["filename"],
            byteCount: row["byte_count"],
            savedAt: Date(timeIntervalSince1970: row["saved_at"])
        )
    }
}
