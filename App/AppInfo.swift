import Foundation

/// Metadata owned by the app target. Kept separate from `ChanCore` so the packages
/// stay bundle-agnostic and testable on Linux.
enum AppInfo {
    static let displayName = "4chios"

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.viceduong.ch4ios"
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
