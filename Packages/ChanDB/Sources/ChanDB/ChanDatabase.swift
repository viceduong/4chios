import ChanCore
import Foundation

/// Where the SQLite file lives and how the schema is versioned.
///
/// The concrete GRDB stack lands in M1; this type exists now so the module boundary,
/// the migration contract, and the file location are fixed before any table is written.
public enum ChanDatabase {
    /// File name of the SQLite database inside Application Support.
    public static let fileName = "chan.sqlite"

    /// Schema version persisted in the `meta` table. Must match `ChanVersion.schemaVersion`.
    public static var schemaVersion: Int { ChanVersion.schemaVersion }

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
}
