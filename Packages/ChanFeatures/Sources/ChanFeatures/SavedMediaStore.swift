import ChanCore
import Foundation

/// Media downloaded for offline viewing.
///
/// Files live in Application Support, not in Nuke's cache: that cache is
/// evictable and only holds images, whereas a saved thread must still play its
/// webm tomorrow. One directory per board, one file per attachment, named by
/// `tim` so a post's media can be found without a lookup.
enum SavedMediaStore {
    static let directoryName = "SavedMedia"

    static func rootDirectory(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func directory(for board: BoardID, fileManager: FileManager = .default) throws -> URL {
        let directory = try rootDirectory(fileManager: fileManager)
            .appendingPathComponent(board.rawValue, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func fileName(tim: Int, ext: String) -> String {
        "\(tim)\(ext.hasPrefix(".") ? ext : ".\(ext)")"
    }

    /// The local file for an attachment, or nil when it has not been downloaded.
    static func localURL(board: BoardID, tim: Int, ext: String, fileManager: FileManager = .default) -> URL? {
        guard let directory = try? directory(for: board, fileManager: fileManager) else { return nil }
        let url = directory.appendingPathComponent(fileName(tim: tim, ext: ext))
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes a downloaded file, returning its size in bytes.
    @discardableResult
    static func store(_ data: Data, board: BoardID, tim: Int, ext: String, fileManager: FileManager = .default) throws -> Int {
        let url = try directory(for: board, fileManager: fileManager)
            .appendingPathComponent(fileName(tim: tim, ext: ext))
        try data.write(to: url, options: .atomic)
        return data.count
    }

    /// Deletes every file for a board, or all of them.
    static func delete(board: BoardID? = nil, fileManager: FileManager = .default) throws {
        let target: URL
        if let board {
            target = try directory(for: board, fileManager: fileManager)
        } else {
            target = try rootDirectory(fileManager: fileManager)
        }
        guard fileManager.fileExists(atPath: target.path) else { return }
        try fileManager.removeItem(at: target)
    }

    /// Bytes on disk, measured rather than trusted from the database, so a
    /// half-written or externally removed file cannot skew the figure.
    static func bytesOnDisk(fileManager: FileManager = .default) -> Int {
        guard let root = try? rootDirectory(fileManager: fileManager),
              let enumerator = fileManager.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return 0 }

        var total = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }
}
