import CoreGraphics

/// Spacing, radius, and motion tokens. Values are deliberately few — a small scale
/// is what keeps a large app visually coherent.
public enum ChanSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum ChanRadius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 18
    public static let card: CGFloat = 14
}

public enum ChanMotion {
    /// Snappy, for taps and toggles.
    public static let quick = 0.18
    /// Standard transition duration.
    public static let standard = 0.28
    /// Slower, for hero image zoom and sheet presentation.
    public static let hero = 0.42
}
