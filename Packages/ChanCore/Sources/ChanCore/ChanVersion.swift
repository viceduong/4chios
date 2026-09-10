import Foundation

/// Version information for the app and its data schema.
public enum ChanVersion {
    /// Marketing version, kept in sync with `project.yml`.
    public static let current = "0.2.4"
    /// Local database schema version. Bump with every migration.
    public static let schemaVersion = 5
}
