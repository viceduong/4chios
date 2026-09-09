import ChanAPI
import ChanCore
import ChanDB
import ChanUI
import Foundation
import SwiftUI

/// The composition root. Screens never construct clients or databases themselves.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let client: ChanClient
    public let database: ChanDatabase
    public let settings: ChanSettings

    public init(client: ChanClient, database: ChanDatabase, settings: ChanSettings) {
        self.client = client
        self.database = database
        self.settings = settings
    }

    /// Production wiring: on-disk database, live network, persisted settings.
    @MainActor public static let shared = AppEnvironment.live()

    public static func live() -> AppEnvironment {
        let database: ChanDatabase
        do {
            database = try ChanDatabase.openDefault()
        } catch {
            // A corrupt or unreadable store must not brick the app.
            database = try! ChanDatabase(inMemory: true)
        }
        return AppEnvironment(client: ChanClient(), database: database, settings: ChanSettings())
    }
}

/// User-visible preferences, persisted in `UserDefaults`.
@MainActor
public final class ChanSettings: ObservableObject {
    public enum ThemeMode: String, CaseIterable, Codable, Identifiable {
        case system, light, dark, oled

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            case .oled: return "OLED Black"
            }
        }
    }

    @Published public var themeMode: ThemeMode {
        didSet { save() }
    }

    @Published public var fontSize: CGFloat {
        didSet { save() }
    }

    @Published public var favoriteBoards: [BoardID] {
        didSet { save() }
    }

    @Published public var showThumbnails: Bool {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
        let storedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? CGFloat(storedSize) : 15
        favoriteBoards = (defaults.stringArray(forKey: Keys.favoriteBoards) ?? []).map { BoardID($0) }
        showThumbnails = defaults.object(forKey: Keys.showThumbnails) as? Bool ?? true
    }

    /// Resolves the effective theme for a color scheme.
    public func theme(for scheme: ColorScheme) -> ChanTheme {
        switch themeMode {
        case .system: return scheme == .dark ? .dark : .light
        case .light: return .light
        case .dark: return .dark
        case .oled: return .oled
        }
    }

    public func toggleFavorite(_ board: BoardID) {
        if let index = favoriteBoards.firstIndex(of: board) {
            favoriteBoards.remove(at: index)
        } else {
            favoriteBoards.append(board)
        }
    }

    public func isFavorite(_ board: BoardID) -> Bool {
        favoriteBoards.contains(board)
    }

    private func save() {
        defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        defaults.set(Double(fontSize), forKey: Keys.fontSize)
        defaults.set(favoriteBoards.map(\.rawValue), forKey: Keys.favoriteBoards)
        defaults.set(showThumbnails, forKey: Keys.showThumbnails)
    }

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let fontSize = "settings.fontSize"
        static let favoriteBoards = "settings.favoriteBoards"
        static let showThumbnails = "settings.showThumbnails"
    }
}
