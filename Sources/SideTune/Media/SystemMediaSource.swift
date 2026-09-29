import AppKit

/// System-wide now playing (any app) through ungive/mediaremote-adapter.
///
/// Since macOS 15.4 only Apple-entitled processes may use MediaRemote, so the adapter
/// runs `/usr/bin/perl` (entitled) which loads a helper framework and streams JSON lines.
final class SystemMediaSource {
    /// Called on the main queue.
    var onUpdate: ((NowPlaying?) -> Void)?

    private let script: URL
    private let framework: URL
    private let queue = DispatchQueue(label: "SideTune.mediaremote")
    private var process: Process?
    private var stopped = true
    private var restartDelay: TimeInterval = 1

    // Confined to `queue`.
    private var buffer = Data()
    private var state: [String: Any] = [:]
    private var artwork: NSImage?
    private var artworkKey = ""

    init?(resources: URL? = Bundle.main.resourceURL) {
        guard let resources else { return nil }
        script = resources.appendingPathComponent("mediaremote-adapter.pl")
        framework = resources.appendingPathComponent("MediaRemoteAdapter.framework")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path), fm.fileExists(atPath: framework.path) else { return nil }
    }

    func start() {
        guard stopped else { return }
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        let args: [String]
        switch command {
        case .play: args = ["send", "0"]
        case .pause: args = ["send", "1"]
        case .togglePlayPause: args = ["send", "2"]
        case .next: args = ["send", "4"]
        case .previous: args = ["send", "5"]
        case .seek(let t): args = ["seek", String(Int64(max(t, 0) * 1_000_000))]
        case .setShuffle, .setRepeat: return // Routed to AppleScript by MediaRouter.
        }
        let p = makeProcess(args)
        try? p.run()
    }

    private func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [script.path, framework.path] + args
        p.standardError = FileHandle.nullDevice
        return p
    }

    private func launch() {
        let p = makeProcess(["stream", "--micros", "--debounce=40"])
        let pipe = Pipe()
        p.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.queue.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped else { return }
                // Adapter died (e.g. perl update); back off and restart.
                self.queue.async { self.buffer.removeAll(); self.state.removeAll() }
                DispatchQueue.main.asyncAfter(deadline: .now() + self.restartDelay) { [weak self] in
                    guard let self, !self.stopped else { return }
                    self.restartDelay = min(self.restartDelay * 2, 30)
                    self.launch()
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            NSLog("SideTune: failed to start mediaremote-adapter: \(error)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { handle(Data(line)) }
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return }
        let diff = object["diff"] as? Bool ?? false

        if diff {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload
        }

        if let value = payload["artworkData"] {
            if let base64 = value as? String, let data = Data(base64Encoded: base64), let image = NSImage(data: data) {
                artwork = image
                artworkKey = UUID().uuidString
            } else {
                artwork = nil
                artworkKey = ""
            }
        } else if !diff {
            artwork = nil
            artworkKey = ""
        }

        let np = makeNowPlaying()
        DispatchQueue.main.async { [weak self] in
            self?.restartDelay = 1
            self?.onUpdate?(np)
        }
    }

    private func makeNowPlaying() -> NowPlaying? {
        guard let title = state["title"] as? String, !title.isEmpty,
              let bundle = (state["parentApplicationBundleIdentifier"] as? String) ?? (state["bundleIdentifier"] as? String)
        else { return nil }
        let micros = { (key: String) -> Double? in (self.state[key] as? NSNumber)?.doubleValue }
        let playing = state["playing"] as? Bool ?? false
        var rate = (state["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        if playing && rate <= 0 { rate = 1 }
        let timestamp = micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        return NowPlaying(
            bundleID: bundle,
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            duration: (micros("durationMicros") ?? 0) / 1_000_000,
            elapsed: (micros("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: timestamp,
            isPlaying: playing,
            playbackRate: rate,
            artwork: artwork,
            artworkKey: artworkKey
        )
    }
}
