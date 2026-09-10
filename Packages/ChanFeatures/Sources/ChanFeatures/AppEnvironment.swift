import ChanAI
import ChanAPI
import ChanCore
import ChanDB
import ChanUI
import Foundation
import SwiftUI

/// The composition root. Screens never construct clients or databases themselves.
@MainActor
public final class AppEnvironment: ObservableObject {
    public let rateLimiter: ChanRateLimiter
    public let client: ChanClient
    public let poster: ChanPoster
    public let database: ChanDatabase
    public let settings: ChanSettings

    public init(
        rateLimiter: ChanRateLimiter,
        client: ChanClient,
        poster: ChanPoster,
        database: ChanDatabase,
        settings: ChanSettings
    ) {
        self.rateLimiter = rateLimiter
        self.client = client
        self.poster = poster
        self.database = database
        self.settings = settings
    }

    /// Production wiring: one shared 1 req/s limiter, on-disk database, persisted settings.
    @MainActor public static let shared = AppEnvironment.live()

    public static func live() -> AppEnvironment {
        let database: ChanDatabase
        do {
            database = try ChanDatabase.openDefault()
        } catch {
            // A corrupt or unreadable store must not brick the app.
            database = try! ChanDatabase(inMemory: true)
        }

        let rateLimiter = ChanRateLimiter()
        return AppEnvironment(
            rateLimiter: rateLimiter,
            client: ChanClient(rateLimiter: rateLimiter),
            poster: ChanPoster(rateLimiter: rateLimiter),
            database: database,
            settings: ChanSettings()
        )
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

    // MARK: - AI summaries

    /// OpenAI-compatible endpoint. Defaults to General Compute, which serves
    /// `gemma-4-31B-it` (text + image input).
    @Published public var aiEndpoint: String {
        didSet { save() }
    }

    @Published public var aiModel: String {
        didSet { save() }
    }

    /// Held in the Keychain, never in UserDefaults.
    @Published public var aiAPIKey: String {
        didSet { ChanKeychain.set(aiAPIKey, for: Keys.aiAPIKey) }
    }

    public var isAIConfigured: Bool {
        !aiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var aiConfiguration: AIConfiguration {
        AIConfiguration(
            baseURL: URL(string: aiEndpoint) ?? AIConfiguration.generalComputeBaseURL,
            apiKey: aiAPIKey,
            model: aiModel.isEmpty ? AIConfiguration.generalComputeModel : aiModel
        )
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        themeMode = ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system
        let storedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = storedSize > 0 ? CGFloat(storedSize) : 15
        favoriteBoards = (defaults.stringArray(forKey: Keys.favoriteBoards) ?? []).map { BoardID($0) }
        showThumbnails = defaults.object(forKey: Keys.showThumbnails) as? Bool ?? true

        aiEndpoint = defaults.string(forKey: Keys.aiEndpoint)
            ?? AIConfiguration.generalComputeBaseURL.absoluteString
        aiModel = defaults.string(forKey: Keys.aiModel) ?? AIConfiguration.generalComputeModel

        // A build-time key (from a gitignored xcconfig) seeds the Keychain once,
        // so local builds work without pasting anything. Never committed.
        if let stored = ChanKeychain.string(for: Keys.aiAPIKey) {
            aiAPIKey = stored
        } else if let injected = Bundle.main.object(forInfoDictionaryKey: "GeneralComputeAPIKey") as? String,
                  !injected.isEmpty {
            aiAPIKey = injected
            ChanKeychain.set(injected, for: Keys.aiAPIKey)
        } else {
            aiAPIKey = ""
        }
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
        defaults.set(aiEndpoint, forKey: Keys.aiEndpoint)
        defaults.set(aiModel, forKey: Keys.aiModel)
        // The API key deliberately never reaches UserDefaults.
    }

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let fontSize = "settings.fontSize"
        static let favoriteBoards = "settings.favoriteBoards"
        static let showThumbnails = "settings.showThumbnails"
        static let aiEndpoint = "settings.aiEndpoint"
        static let aiModel = "settings.aiModel"
        static let aiAPIKey = "settings.aiAPIKey"
    }
}
