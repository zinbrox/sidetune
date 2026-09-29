import AppKit

/// A player SideTune can drive directly by AppleScript, independent of the system's now-playing app.
struct ScriptableApp {
    let bundleID: String
    /// Divides the reported duration into seconds (Spotify reports milliseconds).
    let durationScale: Double
    let usesArtworkURL: Bool
    /// Repeat modes the app can do, in the order a repeat button cycles through them.
    let repeatCycle: [RepeatMode]

    static let spotify = ScriptableApp(bundleID: "com.spotify.client", durationScale: 1000, usesArtworkURL: true, repeatCycle: [.off, .all])
    static let music = ScriptableApp(bundleID: "com.apple.Music", durationScale: 1, usesArtworkURL: false, repeatCycle: [.off, .all, .one])
    static let all = [spotify, music]
    static func app(_ bundleID: String?) -> ScriptableApp? { all.first { $0.bundleID == bundleID } }

    /// "shuffle<US>repeat": Spotify reports booleans, Music reports `off`/`one`/`all`.
    var modesScript: String {
        let body = usesArtworkURL
            ? "return (shuffling as string) & (ASCII character 31) & (repeating as string)"
            : "return (shuffle enabled as string) & (ASCII character 31) & (song repeat as string)"
        return """
        if application id "\(bundleID)" is not running then return ""
        tell application id "\(bundleID)"
            \(body)
        end tell
        """
    }

    func parseModes(_ text: String) -> (shuffle: Bool, repeatMode: RepeatMode)? {
        let f = text.components(separatedBy: "\u{1F}")
        guard f.count == 2 else { return nil }
        let shuffle = f[0] == "true"
        let repeatMode: RepeatMode = f[1] == "true" ? .all : RepeatMode(rawValue: f[1]) ?? .off
        return (shuffle, repeatMode)
    }

    /// Fields joined by ASCII 31. `is running` never launches the app.
    var stateScript: String {
        let art = usesArtworkURL ? "(artwork url of t)" : "\"\""
        let id = usesArtworkURL ? "(id of t)" : "(persistent ID of t)"
        return """
        if application id "\(bundleID)" is not running then return "notrunning"
        tell application id "\(bundleID)"
            set ps to player state as string
            if ps is "stopped" then return "stopped"
            set t to current track
            set d to ASCII character 31
            return ps & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as string) & d & ((player position) as string) & d & \(art) & d & \(id)
        end tell
        """
    }

    var artworkDataScript: String {
        """
        if application id "\(bundleID)" is not running then return missing value
        tell application id "\(bundleID)" to get raw data of artwork 1 of current track
        """
    }

    func commandScript(_ command: MediaCommand) -> String {
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .seek(let t): verb = String(format: "set player position to %.2f", max(t, 0))
        case .setShuffle(let on):
            verb = usesArtworkURL ? "set shuffling to \(on)" : "set shuffle enabled to \(on)"
        case .setRepeat(let mode):
            verb = usesArtworkURL ? "set repeating to \(mode != .off)" : "set song repeat to \(mode.rawValue)"
        }
        return """
        if application id "\(bundleID)" is running then
            tell application id "\(bundleID)" to \(verb)
        end if
        """
    }
}

/// Polls one scriptable app while it's pinned.
final class ScriptableSource {
    let app: ScriptableApp
    /// Called on the main queue.
    var onUpdate: ((ScriptableState) -> Void)?

    /// NSAppleScript isn't safe to use concurrently; all scripts share one serial queue.
    static let queue = DispatchQueue(label: "SideTune.applescript", qos: .userInitiated)
    private static var compiled: [String: NSAppleScript] = [:]

    private var timer: Timer?
    private var inFlight = false
    private var last: NowPlaying?
    private var artworkCache: (key: String, image: NSImage?)?
    private var artworkLoading: String?

    init(app: ScriptableApp) { self.app = app }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        last = nil
    }

    func send(_ command: MediaCommand) {
        let source = app.commandScript(command)
        Self.queue.async {
            _ = Self.run(source, cache: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.poll() }
        }
    }

    func poll() {
        guard isRunning else {
            last = nil
            onUpdate?(.notRunning)
            return
        }
        guard !inFlight else { return }
        inFlight = true
        let source = app.stateScript
        Self.queue.async {
            let result = Self.run(source, cache: true)
            DispatchQueue.main.async { [weak self] in
                self?.inFlight = false
                self?.handle(result)
            }
        }
    }

    private func handle(_ result: Result<NSAppleEventDescriptor, ScriptError>) {
        switch result {
        case .failure(.denied):
            onUpdate?(.denied)
        case .failure:
            break // Transient (app busy/launching); keep the last state.
        case .success(let descriptor):
            let text = descriptor.stringValue ?? ""
            if text == "notrunning" {
                last = nil
                onUpdate?(.notRunning)
                return
            }
            if text == "stopped" {
                last = nil
                onUpdate?(.running(nil))
                return
            }
            let f = text.components(separatedBy: "\u{1F}")
            guard f.count >= 8 else { return }
            let number = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            let key = f[7]
            var np = NowPlaying(
                bundleID: app.bundleID, title: f[1], artist: f[2], album: f[3],
                duration: number(f[4]) / app.durationScale,
                elapsed: number(f[5]), timestamp: Date(),
                isPlaying: f[0] == "playing",
                artwork: artworkCache?.key == key ? artworkCache?.image : nil,
                artworkKey: key
            )
            // Polls land ~1s apart with jitter; keep the previous time anchor unless it drifted,
            // so the progress bar doesn't stutter backwards every second.
            if let last, last.trackKey == np.trackKey, last.isPlaying == np.isPlaying,
               abs(last.elapsed(at: np.timestamp) - np.elapsed) < 1.5 {
                np.elapsed = last.elapsed
                np.timestamp = last.timestamp
            }
            last = np
            if artworkCache?.key != key { loadArtwork(key: key, url: f[6]) }
            onUpdate?(.running(np))
        }
    }

    private func loadArtwork(key: String, url: String) {
        guard artworkLoading != key else { return }
        artworkLoading = key
        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.artworkLoading = nil
                self.artworkCache = (key, image)
                if var last = self.last, last.artworkKey == key {
                    last.artwork = image
                    self.last = last
                    self.onUpdate?(.running(last))
                }
            }
        }
        if app.usesArtworkURL {
            guard let u = URL(string: url), !url.isEmpty else { return finish(nil) }
            URLSession.shared.dataTask(with: u) { data, _, _ in finish(data.flatMap(NSImage.init(data:))) }.resume()
        } else {
            let source = app.artworkDataScript
            Self.queue.async {
                if case .success(let d) = Self.run(source, cache: true) { finish(NSImage(data: d.data)) } else { finish(nil) }
            }
        }
    }

    enum ScriptError: Error { case denied, failed(Int) }

    /// Whether SideTune may already automate `bundleID`, without ever showing the consent prompt.
    static func hasAutomationPermission(_ bundleID: String) -> Bool {
        var address = AEAddressDesc()
        let id = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, id, id.count, &address) == noErr else { return false }
        defer { AEDisposeDesc(&address) }
        return AEDeterminePermissionToAutomateTarget(&address, typeWildCard, typeWildCard, false) == noErr
    }

    /// Must run on `queue`.
    static func run(_ source: String, cache: Bool) -> Result<NSAppleEventDescriptor, ScriptError> {
        let script: NSAppleScript
        if cache, let existing = compiled[source] {
            script = existing
        } else {
            guard let s = NSAppleScript(source: source) else { return .failure(.failed(0)) }
            if cache { compiled[source] = s }
            script = s
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            return .failure(code == -1743 ? .denied : .failed(code))
        }
        return .success(result)
    }
}
