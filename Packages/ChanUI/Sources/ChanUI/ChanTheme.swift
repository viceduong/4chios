import SwiftUI

/// Semantic color tokens. Views never reference raw colors — they read these,
/// which is what makes theme switching (and OLED black) a one-line change.
public struct ChanTheme {
    public let background: Color
    public let surface: Color
    public let elevated: Color
    public let separator: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let tertiaryText: Color
    public let accent: Color
    /// Greentext.
    public let quote: Color
    public let link: Color
    public let danger: Color
    public let spoilerOverlay: Color

    public init(
        background: Color,
        surface: Color,
        elevated: Color,
        separator: Color,
        primaryText: Color,
        secondaryText: Color,
        tertiaryText: Color,
        accent: Color,
        quote: Color,
        link: Color,
        danger: Color,
        spoilerOverlay: Color
    ) {
        self.background = background
        self.surface = surface
        self.elevated = elevated
        self.separator = separator
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.accent = accent
        self.quote = quote
        self.link = link
        self.danger = danger
        self.spoilerOverlay = spoilerOverlay
    }
}

public extension ChanTheme {
    static let light = ChanTheme(
        background: Color(chanHex: 0xF2F3F5),
        surface: Color(chanHex: 0xFFFFFF),
        elevated: Color(chanHex: 0xFFFFFF),
        separator: Color(chanHex: 0xD8DADF),
        primaryText: Color(chanHex: 0x14161A),
        secondaryText: Color(chanHex: 0x5A616B),
        tertiaryText: Color(chanHex: 0x8A9099),
        accent: Color(chanHex: 0x2E7D32),
        quote: Color(chanHex: 0x789922),
        link: Color(chanHex: 0x1D6FD1),
        danger: Color(chanHex: 0xC62828),
        spoilerOverlay: Color(chanHex: 0x14161A, opacity: 0.92)
    )

    static let dark = ChanTheme(
        background: Color(chanHex: 0x101114),
        surface: Color(chanHex: 0x17191D),
        elevated: Color(chanHex: 0x1F2227),
        separator: Color(chanHex: 0x2A2E35),
        primaryText: Color(chanHex: 0xECEDEF),
        secondaryText: Color(chanHex: 0xA0A6B0),
        tertiaryText: Color(chanHex: 0x6E747E),
        accent: Color(chanHex: 0x6FBF73),
        quote: Color(chanHex: 0x9BBF4A),
        link: Color(chanHex: 0x6FA8F5),
        danger: Color(chanHex: 0xFF6B6B),
        spoilerOverlay: Color(chanHex: 0x000000, opacity: 0.9)
    )

    /// Pure black background for OLED panels — saves real battery on long scrolls.
    static let oled = ChanTheme(
        background: Color(chanHex: 0x000000),
        surface: Color(chanHex: 0x0A0A0C),
        elevated: Color(chanHex: 0x131317),
        separator: Color(chanHex: 0x232328),
        primaryText: Color(chanHex: 0xF2F3F5),
        secondaryText: Color(chanHex: 0x9AA0AA),
        tertiaryText: Color(chanHex: 0x666C76),
        accent: Color(chanHex: 0x6FBF73),
        quote: Color(chanHex: 0x9BBF4A),
        link: Color(chanHex: 0x6FA8F5),
        danger: Color(chanHex: 0xFF6B6B),
        spoilerOverlay: Color(chanHex: 0x000000, opacity: 0.94)
    )
}

private struct ChanThemeKey: EnvironmentKey {
    static let defaultValue = ChanTheme.dark
}

public extension EnvironmentValues {
    var chanTheme: ChanTheme {
        get { self[ChanThemeKey.self] }
        set { self[ChanThemeKey.self] = newValue }
    }
}
