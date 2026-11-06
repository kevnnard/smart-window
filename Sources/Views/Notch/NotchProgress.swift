import Foundation

// MARK: - NotchProgress

/// Pure playback-progress math for the expanded card.
enum NotchProgress {
    /// Position at `now`, interpolated from the last reported elapsed time while playing and frozen
    /// while paused (rate 0). Nil when the duration or elapsed time is unknown, so no progress is invented.
    static func position(elapsed: TimeInterval?, timestamp: Date?, rate: Double,
                         duration: TimeInterval?, now: Date) -> TimeInterval? {
        guard let duration, duration > 0, let elapsed else { return nil }
        let drift = timestamp.map { max(0, now.timeIntervalSince($0)) * rate } ?? 0
        return min(duration, max(0, elapsed + drift))
    }

    /// "m:ss", or "h:mm:ss" from one hour. Fractional seconds are truncated.
    static func format(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
