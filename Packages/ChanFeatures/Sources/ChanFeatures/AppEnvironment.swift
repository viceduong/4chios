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
    public let usage: AIUsageStore

    public init(
        rateLimiter: ChanRateLimiter,
        client: ChanClient,
        poster: ChanPoster,
        database: ChanDatabase,
        settings: ChanSettings,
        usage: AIUsageStore
    ) {
        self.rateLimiter = rateLimiter
        self.client = client
        self.poster = poster
        self.database = database
        self.settings = settings
        self.usage = usage
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
            settings: ChanSettings(),
            usage: AIUsageStore()
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

    /// Catalog ordering, remembered across launches.
    @Published public var catalogSort: CatalogSort {
        didSet { save() }
    }

    /// Ordering for the saved lists, remembered across launches.
    @Published public var savedSort: SavedSort {
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

    /// Search-capable endpoint used when a question needs live results.
    @Published public var aiSearchEndpoint: String {
        didSet { save() }
    }

    @Published public var aiSearchModel: String {
        didSet { save() }
    }

    @Published public var aiSearchAPIKey: String {
        didSet { ChanKeychain.set(aiSearchAPIKey, for: Keys.aiSearchAPIKey) }
    }

    /// An Exa key used directly, so searches bill against Exa's own free
    /// allowance instead of being rented through OpenRouter.
    @Published public var aiExaAPIKey: String {
        didSet { ChanKeychain.set(aiExaAPIKey, for: Keys.aiExaAPIKey) }
    }

    /// Which search backend the plugin uses. Pricing is per request, and
    /// Parallel Turbo is seven times cheaper than the Exa default.
    @Published public var aiSearchEngine: AISearchEngine {
        didSet { save() }
    }

    /// Whether the model decides when to search (free on turns it does not), or
    /// the plugin searches on every message.
    @Published public var aiSearchMode: AISearchMode {
        didSet { save() }
    }

    public var isAIConfigured: Bool {
        !aiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when a search endpoint is configured, so the web toggle can be offered.
    public var canSearchTheWeb: Bool {
        hasDirectSearch || !aiSearchAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var hasDirectSearch: Bool {
        !aiExaAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var aiConfiguration: AIConfiguration {
        AIConfiguration(
            baseURL: URL(string: aiEndpoint) ?? AIConfiguration.generalComputeBaseURL,
            apiKey: aiAPIKey,
            model: aiModel.isEmpty ? AIConfiguration.generalComputeModel : aiModel,
            search: canSearchTheWeb
                ? AIConfiguration.SearchConfiguration(
                    baseURL: URL(string: aiSearchEndpoint) ?? AIConfiguration.openRouterBaseURL,
                    apiKey: aiSearchAPIKey,
                    model: aiSearchModel.isEmpty ? AIConfiguration.openRouterSearchModel : aiSearchModel,
                    engine: aiSearchEngine,
                    mode: aiSearchMode
                )
                : nil,
            directSearch: hasDirectSearch
                ? AIConfiguration.DirectSearchConfiguration(apiKey: aiExaAPIKey)
                : nil
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
        catalogSort = CatalogSort(rawValue: defaults.string(forKey: Keys.catalogSort) ?? "") ?? .bumpOrder
        savedSort = SavedSort(rawValue: defaults.string(forKey: Keys.savedSort) ?? "") ?? .recent

        aiEndpoint = defaults.string(forKey: Keys.aiEndpoint)
            ?? AIConfiguration.generalComputeBaseURL.absoluteString
        aiModel = defaults.string(forKey: Keys.aiModel) ?? AIConfiguration.generalComputeModel
        aiSearchEndpoint = defaults.string(forKey: Keys.aiSearchEndpoint)
            ?? AIConfiguration.openRouterBaseURL.absoluteString
        aiSearchModel = defaults.string(forKey: Keys.aiSearchModel) ?? AIConfiguration.openRouterSearchModel
        aiSearchEngine = AISearchEngine(rawValue: defaults.string(forKey: Keys.aiSearchEngine) ?? "") ?? .exaAuto
        aiSearchMode = AISearchMode(rawValue: defaults.string(forKey: Keys.aiSearchMode) ?? "") ?? .serverTool

        // A build-time key (from a gitignored xcconfig) seeds the Keychain once,
        // so local builds work without pasting anything. Never committed.
        if let exaKey = ChanKeychain.string(for: Keys.aiExaAPIKey) {
            aiExaAPIKey = exaKey
        } else if let injected = Bundle.main.object(forInfoDictionaryKey: "ExaAPIKey") as? String,
                  !injected.isEmpty {
            aiExaAPIKey = injected
            ChanKeychain.set(injected, for: Keys.aiExaAPIKey)
        } else {
            aiExaAPIKey = ""
        }

        if let searchKey = ChanKeychain.string(for: Keys.aiSearchAPIKey) {
            aiSearchAPIKey = searchKey
        } else if let injected = Bundle.main.object(forInfoDictionaryKey: "OpenRouterAPIKey") as? String,
                  !injected.isEmpty {
            aiSearchAPIKey = injected
            ChanKeychain.set(injected, for: Keys.aiSearchAPIKey)
        } else {
            aiSearchAPIKey = ""
        }

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
        defaults.set(catalogSort.rawValue, forKey: Keys.catalogSort)
        defaults.set(savedSort.rawValue, forKey: Keys.savedSort)
        defaults.set(aiEndpoint, forKey: Keys.aiEndpoint)
        defaults.set(aiModel, forKey: Keys.aiModel)
        defaults.set(aiSearchEndpoint, forKey: Keys.aiSearchEndpoint)
        defaults.set(aiSearchModel, forKey: Keys.aiSearchModel)
        defaults.set(aiSearchEngine.rawValue, forKey: Keys.aiSearchEngine)
        defaults.set(aiSearchMode.rawValue, forKey: Keys.aiSearchMode)
        // The API key deliberately never reaches UserDefaults.
    }

    private enum Keys {
        static let themeMode = "settings.themeMode"
        static let fontSize = "settings.fontSize"
        static let favoriteBoards = "settings.favoriteBoards"
        static let showThumbnails = "settings.showThumbnails"
        static let catalogSort = "settings.catalogSort"
        static let savedSort = "settings.savedSort"
        static let aiEndpoint = "settings.aiEndpoint"
        static let aiModel = "settings.aiModel"
        static let aiAPIKey = "settings.aiAPIKey"
        static let aiSearchEndpoint = "settings.aiSearchEndpoint"
        static let aiSearchModel = "settings.aiSearchModel"
        static let aiSearchAPIKey = "settings.aiSearchAPIKey"
        static let aiSearchEngine = "settings.aiSearchEngine"
        static let aiExaAPIKey = "settings.aiExaAPIKey"
        static let aiSearchMode = "settings.aiSearchMode"
    }
}
