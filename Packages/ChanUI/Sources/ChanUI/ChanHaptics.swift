import UIKit

/// Thin, consistent haptic vocabulary. Screens call these instead of touching
/// `UIFeedbackGenerator` directly, so the feel stays uniform.
public enum ChanHaptics {
    public static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func softTap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    public static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
