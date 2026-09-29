import AppKit
import Combine
import SwiftUI

struct SourceInfo: Identifiable, Equatable {
    let bundleID: String
    let name: String
    /// True for apps SideTune can control even while another app is the system's now playing.
    let canTargetControl: Bool
    var id: String { bundleID }
}

/// Combines the system now-playing stream with pinned AppleScript players, and routes commands.
@MainActor
final class MediaRouter: ObservableObject {
    @Published private(set) var resolution = Resolution.idle
    @Published private(set) var accent = Theme.fallbackAccent
    @Published private(set) var sources: [SourceInfo] = []
    /// +1 when the last track change moved forward (next, or a new track), -1 for previous.
    /// Drives the direction of track-change slide animations.
    @Published private(set) var trackDirection: CGFloat = 1

    private let settings: Settings
    private let system: SystemMediaSource?
    private var scriptables: [String: ScriptableSource] = [:]
    private var systemState: NowPlaying?
    private var scriptableStates: [String: ScriptableState] = [:]
    private var lastSeen: [String: NowPlaying] = [:]
    private var accentKey: String?
    private var pendingDirection: (value: CGFloat, until: Date)?
    /// Shuffle/repeat of the displayed app, read over AppleScript (MediaRemote doesn't report them).
    private var modes: (bundleID: String, shuffle: Bool, repeatMode: RepeatMode)?
    private var modesTimer: Timer?
    private var modesInFlight = false
    private var bag = Set<AnyCancellable>()

    private let scriptableIDs = Set(ScriptableApp.all.map(\.bundleID))

    var hasSystemSource: Bool { system != nil }

    init(settings: Settings) {
        self.settings = settings
        system = SystemMediaSource()
        for app in ScriptableApp.all {
            let source = ScriptableSource(app: app)
            source.onUpdate = { [weak self] state in self?.scriptableUpdated(app.bundleID, state) }
            scriptables[app.bundleID] = source
        }
    }

    func start() {
        if system == nil { NSLog("SideTune: mediaremote-adapter not bundled; only Spotify/Music will work (pinned).") }
        system?.onUpdate = { [weak self] np in self?.systemUpdated(np) }
        system?.start()

        settings.$pinnedBundleID
            .removeDuplicates()
            .sink { [weak self] pinned in
                DispatchQueue.main.async { self?.pinChanged(pinned) }
            }
            .store(in: &bag)

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.publisher(for: name)
                .sink { [weak self] _ in
                    self?.refreshSources()
                    if let pinned = self?.settings.pinnedBundleID { self?.scriptables[pinned]?.poll() }
                }
                .store(in: &bag)
        }
        refreshSources()

        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollModes() }
        }
        RunLoop.main.add(t, forMode: .common)
        modesTimer = t
    }

    /// Shuffle/repeat buttons are offered for apps SideTune can script.
    var supportsModes: Bool { ScriptableApp.app(resolution.nowPlaying?.bundleID) != nil }

    private func pollModes() {
        guard !modesInFlight, let id = resolution.nowPlaying?.bundleID, let app = ScriptableApp.app(id), AppInfo.isRunning(id) else { return }
        modesInFlight = true
        ScriptableSource.queue.async {
            // Only read when already permitted: polling must never pop the consent dialog.
            var parsed: (shuffle: Bool, repeatMode: RepeatMode)?
            if ScriptableSource.hasAutomationPermission(id), case .success(let d) = ScriptableSource.run(app.modesScript, cache: true) {
                parsed = app.parseModes(d.stringValue ?? "")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.modesInFlight = false
                if let parsed {
                    self.modes = (id, parsed.shuffle, parsed.repeatMode)
                    self.recompute()
                }
            }
        }
    }

    private func sendModeCommand(_ command: MediaCommand) {
        guard let id = resolution.nowPlaying?.bundleID, let app = ScriptableApp.app(id) else { return }
        var current = modes?.bundleID == id ? modes! : (id, false, .off)
        if case .setShuffle(let on) = command { current.shuffle = on }
        if case .setRepeat(let mode) = command { current.repeatMode = mode }
        modes = current
        recompute()
        let source = app.commandScript(command)
        // A user-initiated click may show the Automation consent prompt; that's expected.
        ScriptableSource.queue.async {
            _ = ScriptableSource.run(source, cache: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.pollModes() }
        }
    }

    /// Next repeat mode for the displayed app.
    var nextRepeatMode: RepeatMode {
        let cycle = ScriptableApp.app(resolution.nowPlaying?.bundleID)?.repeatCycle ?? [.off, .all]
        let current = resolution.nowPlaying?.repeatMode ?? .off
        let i = cycle.firstIndex(of: current) ?? 0
        return cycle[(i + 1) % cycle.count]
    }

    func stop() {
        system?.stop()
        scriptables.values.forEach { $0.stop() }
    }

    func pin(_ bundleID: String?) {
        settings.pinnedBundleID = bundleID
    }

    func send(_ command: MediaCommand) {
        if case .setShuffle = command { return sendModeCommand(command) }
        if case .setRepeat = command { return sendModeCommand(command) }
        let now = Date()
        if command == .next { pendingDirection = (1, now.addingTimeInterval(3)) }
        if command == .previous { pendingDirection = (-1, now.addingTimeInterval(3)) }
        switch resolution.target {
        case .none:
            return
        case .system:
            system?.send(command)
            // Optimistic update so the button reacts instantly; the stream confirms shortly after.
            if let np = systemState { systemState = optimistic(np, command, now) }
        case .scriptable(let id):
            scriptables[id]?.send(command)
            if case .running(let np?) = scriptableStates[id] { scriptableStates[id] = .running(optimistic(np, command, now)) }
        }
        recompute()
    }

    private func optimistic(_ np: NowPlaying, _ command: MediaCommand, _ now: Date) -> NowPlaying {
        switch command {
        case .togglePlayPause: return np.withPlaying(!np.isPlaying, at: now)
        case .play: return np.withPlaying(true, at: now)
        case .pause: return np.withPlaying(false, at: now)
        case .seek(let t):
            var c = np
            c.elapsed = t
            c.timestamp = now
            return c
        case .next, .previous, .setShuffle, .setRepeat: return np
        }
    }

    // MARK: Updates

    private func systemUpdated(_ np: NowPlaying?) {
        systemState = np
        if let np { remember(np) }
        recompute()
    }

    private func scriptableUpdated(_ id: String, _ state: ScriptableState) {
        scriptableStates[id] = state
        if case .running(let np?) = state { remember(np) }
        recompute()
    }

    private func remember(_ np: NowPlaying) {
        let isNew = lastSeen[np.bundleID] == nil
        lastSeen[np.bundleID] = np
        if isNew { refreshSources() }
    }

    private func pinChanged(_ pinned: String?) {
        for (id, source) in scriptables {
            if id == pinned { source.start() } else { source.stop(); scriptableStates[id] = nil }
        }
        refreshSources()
        recompute()
    }

    private func recompute() {
        var r = RouterLogic.resolve(
            system: systemState, scriptable: scriptableStates, scriptableApps: scriptableIDs,
            pinned: settings.pinnedBundleID, lastSeen: lastSeen
        )
        if let m = modes, m.bundleID == r.nowPlaying?.bundleID {
            r.nowPlaying?.shuffle = m.shuffle
            r.nowPlaying?.repeatMode = m.repeatMode
        }
        if r.nowPlaying?.trackKey != resolution.nowPlaying?.trackKey {
            let pending = pendingDirection.flatMap { $0.until > Date() ? $0.value : nil }
            trackDirection = pending ?? 1
            pendingDirection = nil
        }
        if r != resolution { resolution = r }
        let key = r.nowPlaying?.artworkKey ?? ""
        if key != accentKey {
            accentKey = key
            let color = Theme.accent(from: r.nowPlaying?.artwork)
            withAnimation(.easeInOut(duration: 0.6)) { accent = color }
        }
    }

    private func refreshSources() {
        var ids: [String] = []
        func add(_ id: String) { if !ids.contains(id) { ids.append(id) } }
        if let current = systemState?.bundleID { add(current) }
        ScriptableApp.all.map(\.bundleID).filter(AppInfo.isRunning).forEach(add)
        lastSeen.keys.sorted().forEach(add)
        if let pinned = settings.pinnedBundleID { add(pinned) }
        let list = ids.map { SourceInfo(bundleID: $0, name: AppInfo.name($0), canTargetControl: scriptableIDs.contains($0)) }
        if list != sources { sources = list }
    }
}

#if PREVIEW
extension MediaRouter {
    /// Used by scripts/preview.sh to render the UI with sample data.
    func previewSet(_ r: Resolution) {
        resolution = r
        accent = Theme.accent(from: r.nowPlaying?.artwork)
    }
}
#endif
