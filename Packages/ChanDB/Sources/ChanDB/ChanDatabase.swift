import ChanCore
import Foundation
import GRDB

/// The local cache of everything the app has seen.
///
/// Design choice: this is a **document store**, not a relational mirror of the
/// API. Each post and board is stored as JSON in a blob column, with only the
/// columns we actually query (`board_id`, `op_no`, `no`, `time`) lifted out.
/// That keeps the schema stable as the API evolves and removes hundreds of lines
/// of field-by-field mapping. Full-text search uses a separate FTS5 table.
public final class ChanDatabase: @unchecked Sendable {
    /// File name of the SQLite database inside Application Support.
    public static let fileName = "chan.sqlite"
    /// Schema version persisted in `meta`. Must match `ChanVersion.schemaVersion`.
    public static var schemaVersion: Int { ChanVersion.schemaVersion }

    let writer: any DatabaseWriter

    // MARK: - Init

    /// Opens (or creates) the database at `url`, running migrations.
    public init(url: URL) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        writer = pool
        try migrate()
    }

    /// An in-memory database, used by tests and previews.
    public init(inMemory: Bool = true) throws {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(configuration: configuration)
        writer = queue
        try migrate()
    }

    /// Opens the database in Application Support, creating the directory if needed.
    public static func openDefault(fileManager: FileManager = .default) throws -> ChanDatabase {
        try ChanDatabase(url: defaultURL(fileManager: fileManager))
    }

    /// Application Support directory, created on demand.
    public static func defaultDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("ChanDB", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Full path of the database file, creating its directory if needed.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        try defaultDirectory(fileManager: fileManager).appendingPathComponent(fileName)
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.migrator().migrate(writer)
    }

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "board") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("ws_board", .boolean).notNull().defaults(to: false)
                table.column("json", .text).notNull()
            }

            try db.create(table: "thread") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("time", .double).notNull()
                table.column("last_modified", .double)
                table.column("replies", .integer)
                table.column("images", .integer)
                table.column("sticky", .boolean).notNull().defaults(to: false)
                table.column("closed", .boolean).notNull().defaults(to: false)
                table.column("archived", .boolean).notNull().defaults(to: false)
                table.column("seen_at", .double).notNull()
                table.column("json", .text).notNull()
                table.primaryKey(["board_id", "op_no"])
            }
            try db.create(index: "thread_board_modified", on: "thread", columns: ["board_id", "last_modified"])

            try db.create(table: "post") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("no", .integer).notNull()
                table.column("time", .double).notNull()
                table.column("is_op", .boolean).notNull().defaults(to: false)
                table.column("json", .text).notNull()
                table.primaryKey(["board_id", "no"])
            }
            try db.create(index: "post_thread", on: "post", columns: ["board_id", "op_no", "no"])

            try db.create(table: "bookmark") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("added_at", .double).notNull()
                table.column("note", .text)
                table.primaryKey(["board_id", "op_no"])
            }

            try db.create(table: "watch") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("added_at", .double).notNull()
                table.column("last_seen_reply", .integer).notNull().defaults(to: 0)
                table.column("notify", .boolean).notNull().defaults(to: true)
                table.primaryKey(["board_id", "op_no"])
            }

            try db.create(table: "filter") { table in
                table.column("id", .integer).primaryKey(autoincrement: true)
                table.column("board_id", .text)
                table.column("kind", .text).notNull()
                table.column("pattern", .text).notNull()
                table.column("action", .text).notNull()
                table.column("enabled", .boolean).notNull().defaults(to: true)
                table.column("created_at", .double).notNull()
            }

            try db.create(table: "read_state") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("last_read_no", .integer).notNull().defaults(to: 0)
                table.primaryKey(["board_id", "op_no"])
            }

            try db.create(table: "meta") { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text).notNull()
            }

            try db.execute(sql: """
                CREATE VIRTUAL TABLE post_fts USING fts5(
                    com_plain,
                    board_id UNINDEXED,
                    op_no UNINDEXED,
                    no UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 2'
                )
                """)
        }

        // v2: posts the user wrote, so quotes aimed at them can be marked "(You)".
        migrator.registerMigration("v2") { db in
            try db.create(table: "my_post") { table in
                table.column("board_id", .text).notNull()
                table.column("no", .integer).notNull()
                table.column("thread_no", .integer).notNull()
                table.column("created_at", .double).notNull()
                table.primaryKey(["board_id", "no"])
            }
            try db.create(index: "my_post_thread", on: "my_post", columns: ["board_id", "thread_no"])
        }

        // v3: the filter rule language grew fields, match modes and board scopes,
        // so rules are stored as a JSON document. Legacy columns are kept so rows
        // written by earlier builds still load.
        migrator.registerMigration("v3") { db in
            try db.alter(table: "filter") { table in
                table.add(column: "json", .text)
            }
        }

        // v4: cached AI summaries, keyed by thread and model so switching models
        // does not invalidate the other's summary.
        migrator.registerMigration("v4") { db in
            try db.create(table: "thread_summary") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("model", .text).notNull()
                table.column("created_at", .double).notNull()
                table.column("post_count", .integer).notNull()
                table.column("json", .text).notNull()
                table.primaryKey(["board_id", "op_no", "model"])
            }
        }

        // v5: the conversation about a thread, so reopening a summary resumes
        // where the reader left off.
        migrator.registerMigration("v5") { db in
            try db.create(table: "thread_chat") { table in
                table.column("board_id", .text).notNull()
                table.column("op_no", .integer).notNull()
                table.column("updated_at", .double).notNull()
                table.column("json", .text).notNull()
                table.primaryKey(["board_id", "op_no"])
            }
        }

        return migrator
    }
    // MARK: - JSON codec

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }
}
