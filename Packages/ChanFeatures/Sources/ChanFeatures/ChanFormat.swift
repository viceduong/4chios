import Foundation

/// Display formatting shared by every screen.
public enum ChanFormat {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy(EEE)HH:mm:ss"
        return formatter
    }()

    /// Compact relative time: `3m`, `2h`, `5d`.
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "\(max(Int(seconds), 0))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// 4chan's own timestamp style: `11/14/23(Tue)22:15:00`.
    public static func postDate(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }

    /// Human file size.
    public static func bytes(_ count: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(count)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0 ? "\(count) B" : String(format: "%.1f %@", value, units[index])
    }

    /// Compact counts: `999`, `1.2k`, `15k`.
    public static func count(_ value: Int) -> String {
        if value < 1000 { return String(value) }
        let thousands = Double(value) / 1000
        if thousands < 10 { return String(format: "%.1fk", thousands) }
        return "\(Int(thousands))k"
    }

    /// Duration for webm badges.
    public static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
