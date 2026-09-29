import Foundation

/// What an AppleScript-controllable player (Spotify, Music) is doing.
enum ScriptableState: Equatable {
    case notRunning
    /// The user refused SideTune's Automation access to the app.
    case denied
    /// Running; nil when stopped with no current track.
    case running(NowPlaying?)
}

/// Where transport commands go.
enum ControlTarget: Equatable {
    case none
    /// The system's current now-playing app, via MediaRemote.
    case system
    /// One specific app, via AppleScript, regardless of what else is playing.
    case scriptable(String)
}

enum PlayerStatus: Equatable {
    case ok
    case idle
    case notRunning(String)
    case noPermission(String)
    /// Pinned app is running but has nothing loaded.
    case pinnedIdle(String)
    /// Pinned app can only be controlled while it's the system's now-playing app, and it isn't.
    case notCurrent(String)
}

struct Resolution: Equatable {
    var nowPlaying: NowPlaying?
    var target: ControlTarget
    var status: PlayerStatus

    static let idle = Resolution(nowPlaying: nil, target: .none, status: .idle)
}

enum RouterLogic {
    /// Decides what to show and whom to control.
    ///
    /// - Automatic (`pinned == nil`): follow the system now-playing app.
    /// - Pinned to a scriptable app: show and control that app only, ignoring the system,
    ///   so a browser that starts playing can't steal the controls.
    /// - Pinned to any other app: follow it while it's the system's current app;
    ///   otherwise show its last known track with controls disabled.
    static func resolve(
        system: NowPlaying?,
        scriptable: [String: ScriptableState],
        scriptableApps: Set<String>,
        pinned: String?,
        lastSeen: [String: NowPlaying],
        now: Date = Date()
    ) -> Resolution {
        guard let pinned else {
            guard let system else { return .idle }
            return Resolution(nowPlaying: system, target: .system, status: .ok)
        }

        let remembered = lastSeen[pinned]?.paused(at: now)

        if scriptableApps.contains(pinned) {
            switch scriptable[pinned] ?? .notRunning {
            case .notRunning:
                return Resolution(nowPlaying: remembered, target: .none, status: .notRunning(pinned))
            case .denied:
                return Resolution(nowPlaying: remembered, target: .none, status: .noPermission(pinned))
            case .running(nil):
                return Resolution(nowPlaying: remembered, target: .scriptable(pinned), status: .pinnedIdle(pinned))
            case .running(let np?):
                return Resolution(nowPlaying: np, target: .scriptable(pinned), status: .ok)
            }
        }

        if let system, system.bundleID == pinned {
            return Resolution(nowPlaying: system, target: .system, status: .ok)
        }
        return Resolution(nowPlaying: remembered, target: .none, status: .notCurrent(pinned))
    }
}
