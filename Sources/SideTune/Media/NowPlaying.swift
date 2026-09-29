import AppKit

/// A snapshot of what a player reports. `elapsed` was true at `timestamp`;
/// use `elapsed(at:)` for the live position.
struct NowPlaying: Equatable {
    var bundleID: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var elapsed: TimeInterval
    var timestamp: Date
    var isPlaying: Bool
    var playbackRate: Double = 1
    var artwork: NSImage?
    /// Changes whenever the artwork changes; drives artwork transitions and color extraction.
    var artworkKey: String
    /// Playback modes; nil when unknown or the app doesn't expose them.
    var shuffle: Bool? = nil
    var repeatMode: RepeatMode? = nil

    var trackKey: String { "\(bundleID)|\(title)|\(artist)|\(album)" }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        var t = elapsed
        if isPlaying { t += date.timeIntervalSince(timestamp) * playbackRate }
        if duration > 0 { t = min(t, duration) }
        return max(t, 0)
    }

    /// The same track, frozen at its current position.
    func paused(at date: Date = Date()) -> NowPlaying {
        var copy = self
        copy.elapsed = elapsed(at: date)
        copy.timestamp = date
        copy.isPlaying = false
        return copy
    }

    /// The same track with play state flipped, keeping the position continuous.
    func withPlaying(_ playing: Bool, at date: Date = Date()) -> NowPlaying {
        var copy = paused(at: date)
        copy.isPlaying = playing
        return copy
    }
}

enum RepeatMode: String, Equatable {
    case off, all, one
}

enum MediaCommand: Equatable {
    case play, pause, togglePlayPause, next, previous
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
}

func formatTime(_ t: TimeInterval) -> String {
    guard t.isFinite, t >= 0 else { return "0:00" }
    let s = Int(t)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
