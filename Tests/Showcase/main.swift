import AppKit
import SwiftUI

// Renders README screenshots and the demo GIF frames from the real SideTune views,
// composed over a generated wallpaper and a mock menu bar. Covers come from the iTunes
// catalog (downloaded by scripts/screenshots.sh); generated art is the fallback.
// Run via scripts/screenshots.sh.

// MARK: Sample content

func makeArtwork(_ colors: [NSColor], seed: Int) -> NSImage {
    NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
        NSGradient(colors: colors)!.draw(in: rect, angle: CGFloat(35 + seed * 40))
        for i in 0..<6 {
            let d = CGFloat(i)
            let r = 90 + d * 38
            let x = 300 + cos(d * 1.7 + CGFloat(seed)) * (60 + d * 22)
            let y = 300 + sin(d * 2.3 + CGFloat(seed)) * (60 + d * 18)
            NSColor.white.withAlphaComponent(0.05 + 0.03 * d).setStroke()
            let ring = NSBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            ring.lineWidth = 10 + d * 3
            ring.stroke()
        }
        let sun = NSBezierPath(ovalIn: CGRect(x: 190, y: 190, width: 220, height: 220))
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.85), colors.last!.withAlphaComponent(0.2)])!.draw(in: sun, angle: -90)
        return true
    }
}

let artDir = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : ""
func cover(_ file: String) -> NSImage? { NSImage(contentsOfFile: "\(artDir)/\(file)") }

let artA = cover("californication.jpg") ?? makeArtwork([NSColor(calibratedRed: 0.98, green: 0.36, blue: 0.52, alpha: 1), NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.78, alpha: 1)], seed: 1)
let artB = cover("everywhere.jpg") ?? makeArtwork([NSColor(calibratedRed: 0.12, green: 0.78, blue: 0.74, alpha: 1), NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.52, alpha: 1)], seed: 2)
let artC = cover("sevennation.jpg") ?? makeArtwork([NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.24, alpha: 1), NSColor(calibratedRed: 0.72, green: 0.18, blue: 0.22, alpha: 1)], seed: 3)

func track(_ title: String, _ artist: String, _ album: String, _ art: NSImage, key: String, playing: Bool = true, elapsed: Double = 83, duration: Double = 214) -> NowPlaying {
    NowPlaying(bundleID: "com.spotify.client", title: title, artist: artist, album: album, duration: duration, elapsed: elapsed,
               timestamp: Date(), isPlaying: playing, artwork: art, artworkKey: key, shuffle: true, repeatMode: .off)
}

let trackA = track("Californication", "Red Hot Chili Peppers", "Californication", artA, key: "a", elapsed: 96, duration: 321)
let trackB = track("Everywhere", "Fleetwood Mac", "Tango in the Night", artB, key: "b", elapsed: 12, duration: 227)
let trackC = track("Seven Nation Army", "The White Stripes", "Elephant", artC, key: "c", elapsed: 58, duration: 232)

// MARK: Scene pieces

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.06, blue: 0.16), Color(red: 0.16, green: 0.08, blue: 0.26)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.85, green: 0.25, blue: 0.6)).frame(width: 620).blur(radius: 150).offset(x: -380, y: -220).opacity(0.7)
            Circle().fill(Color(red: 0.1, green: 0.65, blue: 0.75)).frame(width: 700).blur(radius: 170).offset(x: 420, y: 260).opacity(0.6)
            Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.25)).frame(width: 420).blur(radius: 140).offset(x: 180, y: -260).opacity(0.45)
        }
    }
}

struct MockMenuBar: View {
    var notch = true
    var highlightIcon = false

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.28))
            HStack(spacing: 18) {
                Image(systemName: "applelogo").font(.system(size: 14, weight: .semibold))
                Text("Finder").fontWeight(.bold)
                ForEach(["File", "Edit", "View", "Go", "Window", "Help"], id: \.self) { Text($0) }
                Spacer()
                HStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(highlightIcon ? 0.22 : 0)))
                    Image(systemName: "battery.100percent")
                    Image(systemName: "wifi")
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "switch.2")
                    Text("Mon 9:41")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 18)
            if notch {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 11, bottomTrailing: 11, topTrailing: 0), style: .continuous)
                    .fill(.black)
                    .frame(width: 185, height: 32)
            }
        }
        .frame(height: 32)
    }
}

/// Pointer drawn into the drag demo: arrow normally, closed hand while dragging.
struct FakeCursor: View {
    let position: CGPoint // SwiftUI scene coordinates
    let grabbing: Bool

    var body: some View {
        let image = grabbing ? NSCursor.closedHand.image : NSCursor.arrow.image
        let hot = grabbing ? NSCursor.closedHand.hotSpot : NSCursor.arrow.hotSpot
        Image(nsImage: image)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .offset(x: position.x - hot.x, y: position.y - hot.y)
    }
}

/// Window position and pointer for the drag demo, both in AppKit scene coordinates.
@MainActor
final class DragScene: ObservableObject {
    @Published var origin: CGPoint
    @Published var cursor: CGPoint
    @Published var grabbing = false
    init(origin: CGPoint, cursor: CGPoint) { self.origin = origin; self.cursor = cursor }
}

struct DragStage: View {
    @ObservedObject var scene: DragScene
    @ObservedObject var layout: OverlayLayout
    let router: MediaRouter
    let settings: Settings
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            MockMenuBar()
            Placed(layout: layout, router: router, settings: settings, appKitOrigin: scene.origin, sceneHeight: size.height)
            FakeCursor(position: CGPoint(x: scene.cursor.x, y: size.height - scene.cursor.y), grabbing: scene.grabbing)
        }
    }
}

/// A SideTune overlay window placed in a scene whose AppKit "screen" is `scene` (origin bottom-left).
struct Placed: View {
    @ObservedObject var layout: OverlayLayout
    let router: MediaRouter
    let settings: Settings
    let appKitOrigin: CGPoint
    let sceneHeight: CGFloat

    var body: some View {
        let size = layout.metrics.windowSize
        OverlayRootView(layout: layout, router: router, settings: settings,
                        actions: OverlayActions(dragChanged: {}, dragEnded: {}, expand: {}, close: {}, sourceMenu: {}))
            .frame(width: size.width, height: size.height)
            .offset(x: appKitOrigin.x, y: sceneHeight - appKitOrigin.y - size.height)
    }
}

// MARK: Capture

@MainActor
final class Stage {
    let window: NSWindow
    let out: URL
    private var frame = 0
    private(set) var recordedFrames = 0
    private(set) var recordedTime: Double = 0

    init(size: CGSize, out: URL, root: some View) {
        self.out = out
        // On screen (off-screen windows can't be captured) but at desktop level, behind everything.
        window = NSWindow(contentRect: CGRect(origin: NSScreen.screens[0].visibleFrame.origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.isOpaque = true
        let host = NSHostingView(rootView: root.frame(width: size.width, height: size.height, alignment: .topLeading).clipped().environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
    }

    func settle(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    func shot(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), out.appendingPathComponent(name).path]
        try! p.run()
        p.waitUntilExit()
    }

    /// Captures animation frames for `seconds` of (slowed) time.
    func record(_ seconds: Double, into dir: URL) {
        let start = Date(), end = start.addingTimeInterval(seconds)
        while Date() < end {
            settle(0.02)
            capture(into: dir)
            recordedFrames += 1
        }
        recordedTime += Date().timeIntervalSince(start)
    }

    /// Repeats the current frame, for pauses in the GIF.
    func hold(_ frames: Int, into dir: URL) {
        capture(into: dir)
        let last = dir.appendingPathComponent(String(format: "f%04d.png", frame - 1))
        for _ in 1..<frames {
            try? FileManager.default.copyItem(at: last, to: dir.appendingPathComponent(String(format: "f%04d.png", frame)))
            frame += 1
        }
    }

    func capture(into dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), dir.appendingPathComponent(String(format: "f%04d.png", frame)).path]
        try! p.run()
        p.waitUntilExit()
        frame += 1
    }

    func close() { window.orderOut(nil) }
}

// MARK: Scenes

MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    _ = NSApplication.shared
    VisualEffect.blending = .withinWindow

    let settings = Settings()
    settings.tintWithArtwork = true
    settings.pinnedBundleID = nil
    let router = MediaRouter(settings: settings)
    router.previewSet(Resolution(nowPlaying: trackA, target: .system, status: .ok))

    @MainActor func sideLayout(expanded: Bool, hovering: Bool, peek: Bool = false, scale: CGFloat = 1) -> OverlayLayout {
        let l = OverlayLayout()
        l.metrics.scale = scale
        l.edge = .right
        l.isExpanded = expanded
        l.isHovering = hovering
        l.isPeeking = peek
        l.isVisible = true
        return l
    }

    @MainActor func rightDock(_ l: OverlayLayout, scene: CGSize, along: CGFloat) -> CGPoint {
        l.metrics.windowOrigin(docked: .right, along: along, in: CGRect(x: 0, y: 0, width: scene.width, height: scene.height - 32))
    }

    // 1. Hero: expanded card docked on the right edge.
    do {
        let size = CGSize(width: 1100, height: 560)
        let l = sideLayout(expanded: true, hovering: true)
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            Placed(layout: l, router: router, settings: settings, appKitOrigin: rightDock(l, scene: size, along: 0.5), sceneHeight: size.height)
            MockMenuBar()
        })
        stage.settle(1.2)
        stage.shot("hero.png")
        stage.close()
    }

    // 2. Collapsed tab with the new-track peek.
    do {
        let size = CGSize(width: 560, height: 360)
        let l = sideLayout(expanded: false, hovering: false, peek: true)
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            Placed(layout: l, router: router, settings: settings, appKitOrigin: rightDock(l, scene: size, along: 0.45), sceneHeight: size.height)
            MockMenuBar(notch: false)
        })
        stage.settle(1.0)
        stage.shot("tab.png")
        stage.close()
    }

    // 3. Beside the notch: collapsed wing, and expanded card below it.
    for (name, expanded, height) in [("notch-collapsed.png", false, 110.0), ("notch.png", true, 300.0)] {
        let size = CGSize(width: 1100, height: height)
        let l = OverlayLayout()
        l.edge = .top
        l.isVisible = true
        l.isExpanded = expanded
        l.isHovering = expanded
        let notch = CGRect(x: size.width / 2 - 92.5, y: size.height - 32, width: 185, height: 32)
        let nl = l.metrics.notchLayout(notch: notch, side: .right, in: CGRect(x: 0, y: 0, width: size.width, height: size.height - 32))
        l.notchWing = nl.wing
        l.notchSide = .right
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            MockMenuBar()
            Placed(layout: l, router: router, settings: settings, appKitOrigin: nl.windowOrigin, sceneHeight: size.height)
        })
        stage.settle(1.2)
        stage.shot(name)
        stage.close()
    }

    // 4. Menu bar mini player.
    do {
        let size = CGSize(width: 760, height: 360)
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            MockMenuBar(notch: false, highlightIcon: true)
            MiniPlayer(router: router, settings: settings, showSourceMenu: {}, openSettings: {})
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
                .offset(x: 371, y: 42)
        })
        stage.settle(1.0)
        stage.shot("menubar.png")
        stage.close()
    }

    // 5. Sizes: smallest and largest, floating.
    do {
        router.previewSet(Resolution(nowPlaying: trackC, target: .system, status: .ok))
        let size = CGSize(width: 1100, height: 400)
        let small = OverlayLayout(); small.metrics.scale = OverlayMetrics.scaleRange.lowerBound; small.isVisible = true
        let large = OverlayLayout(); large.metrics.scale = OverlayMetrics.scaleRange.upperBound; large.isVisible = true
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            Placed(layout: small, router: router, settings: settings, appKitOrigin: CGPoint(x: 10, y: 70), sceneHeight: size.height)
            Placed(layout: large, router: router, settings: settings, appKitOrigin: CGPoint(x: 400, y: 20), sceneHeight: size.height)
        })
        stage.settle(1.2)
        stage.shot("sizes.png")
        stage.close()
        router.previewSet(Resolution(nowPlaying: trackA, target: .system, status: .ok))
    }

    // 6. Demo GIF frames: hover to expand, skip a track, pause, collapse.
    do {
        let frames = out.appendingPathComponent("demo-frames")
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let size = CGSize(width: 720, height: 360)
        let l = sideLayout(expanded: false, hovering: false)
        let stage = Stage(size: size, out: out, root: ZStack(alignment: .topLeading) {
            Wallpaper()
            Placed(layout: l, router: router, settings: settings, appKitOrigin: rightDock(l, scene: size, along: 0.42), sceneHeight: size.height)
            MockMenuBar(notch: false)
        })
        stage.settle(1.0)
        Theme.slowdown = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "6")!
        Theme.slowdownStart = Date()
        let slow = Theme.slowdown
        // Every moment is recorded (no repeated frames) so the progress bar ticks at real speed.
        @MainActor func step(_ seconds: Double) { stage.record(seconds * slow, into: frames) }
        @MainActor func now() -> Date { Theme.playbackDate(Date()) }
        @MainActor func playing(_ t: NowPlaying) -> NowPlaying { var c = t; c.timestamp = now(); return c }

        router.previewSet(Resolution(nowPlaying: playing(trackA), target: .system, status: .ok))
        step(0.35)
        withAnimation(Theme.snappy) { l.isHovering = true }
        step(0.15)
        withAnimation(Theme.morph) { l.isExpanded = true }
        step(1.3)
        // Skipping starts the next song from the top.
        var next = playing(trackB)
        next.elapsed = 0
        withAnimation(Theme.morph) { router.previewSet(Resolution(nowPlaying: next, target: .system, status: .ok), direction: 1) }
        step(1.4)
        let paused = router.resolution.nowPlaying!.paused(at: now())
        withAnimation(Theme.morph) { router.previewSet(Resolution(nowPlaying: paused, target: .system, status: .ok), direction: 1) }
        step(1.0)
        withAnimation(Theme.morph) {
            l.isHovering = false
            l.isExpanded = false
        }
        step(1.0)
        stage.close()
        // Playback rate that makes recorded (slowed) motion play at real speed.
        let fps = Double(stage.recordedFrames) / (stage.recordedTime / slow)
        try! String(format: "%.2f", fps).write(to: out.appendingPathComponent("demo-fps.txt"), atomically: true, encoding: .utf8)
    }

    // 7. Drag tour: floating → right edge → along the edge → beside the notch → left edge.
    do {
        let frames = out.appendingPathComponent("drag-frames")
        try? FileManager.default.removeItem(at: frames)
        try! FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        Theme.slowdown = 1

        let size = CGSize(width: 1000, height: 600)
        let vf = CGRect(x: 0, y: 0, width: size.width, height: size.height - 32)
        let notch = CGRect(x: size.width / 2 - 92.5, y: size.height - 32, width: 185, height: 32)
        let l = OverlayLayout()
        l.isVisible = true
        l.isExpanded = true
        l.isHovering = true
        let m = l.metrics
        let p = m.padding
        let grab = CGPoint(x: 205, y: 132) // where the pointer holds the card, from its bottom-left

        let startCard = CGPoint(x: 120, y: 190)
        let scene = DragScene(origin: CGPoint(x: startCard.x - p, y: startCard.y - p),
                              cursor: CGPoint(x: startCard.x + grab.x, y: startCard.y + grab.y))
        router.previewSet(Resolution(nowPlaying: trackA, target: .system, status: .ok))

        let stage = Stage(size: size, out: out, root: DragStage(scene: scene, layout: l, router: router, settings: settings, size: size))
        stage.settle(1.0)
        Theme.slowdown = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "6")!
        Theme.slowdownStart = Date()
        let slow = Theme.slowdown
        var frameCount = 0
        let virtualStart = Theme.playbackDate(Date())

        func still() -> Transaction { var t = Transaction(); t.disablesAnimations = true; return t }
        func ease(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

        /// Runs `update(progress)` every captured frame for `seconds` of on-screen time.
        @MainActor func run(_ seconds: Double, _ update: (Double) -> Void = { _ in }) {
            let begin = Theme.playbackDate(Date())
            while true {
                let v = Theme.playbackDate(Date()).timeIntervalSince(begin) / seconds
                if v >= 1 { break }
                update(v)
                stage.settle(0.01)
                stage.capture(into: frames)
                frameCount += 1
            }
        }

        /// Pointer glides to `to` (not dragging).
        @MainActor func point(to: CGPoint, _ seconds: Double) {
            let from = scene.cursor
            run(seconds) { v in
                let e = CGFloat(ease(v))
                withTransaction(still()) { scene.cursor = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e) }
            }
        }

        /// Drags the card along a gently arced path, with the app's magnet pull, snap preview and sway.
        @MainActor func drag(to: CGPoint, arc: CGFloat, _ seconds: Double) {
            let from = scene.cursor, originStart = scene.origin
            var lastCursor = from, lastTime = Theme.playbackDate(Date())
            run(seconds) { v in
                let e = CGFloat(ease(v))
                let bump = sin(CGFloat(v) * .pi) * arc
                let c = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e + bump)
                var o = CGPoint(x: originStart.x + c.x - from.x, y: originStart.y + c.y - from.y)
                let pull = EdgeSnapper.magnetOffset(card: m.floatingCard(windowOrigin: o), in: vf, threshold: 36, gap: m.dockGap)
                o.x += pull.dx
                o.y += pull.dy
                let preview = EdgeSnapper.nearestEdge(card: m.floatingCard(windowOrigin: o), in: vf, threshold: 36)
                let now = Theme.playbackDate(Date())
                let dt = max(now.timeIntervalSince(lastTime), 0.001)
                let tilt = Double(((c.x - lastCursor.x) / CGFloat(dt) / 400).clamped(to: -5...5))
                lastCursor = c
                lastTime = now
                withTransaction(still()) {
                    scene.cursor = c
                    scene.origin = o
                }
                if preview != l.snapPreview { withAnimation(Theme.snappy) { l.snapPreview = preview } }
                withAnimation(Theme.timed(.interactiveSpring(response: 0.25, dampingFraction: 0.7))) { l.dragTilt = tilt }
            }
        }

        /// Grabs the player where the pointer is: it undocks and opens, as in the app.
        @MainActor func pickUp() {
            withTransaction(still()) {
                scene.grabbing = true
            }
            withAnimation(Theme.morph) {
                l.isDragging = true
                l.edge = nil
                l.notchWing = nil
                l.isExpanded = true
                l.isHovering = true
            }
        }

        /// Lets go: docks to the edge the card is near (or beside the notch), with the dock spring.
        @MainActor func drop(notchSide: NotchSide? = nil) {
            let card = m.floatingCard(windowOrigin: scene.origin)
            scene.grabbing = false
            withAnimation(Theme.timed(.spring(response: 0.5, dampingFraction: 0.4))) { l.dragTilt = 0 }
            withAnimation(Theme.snappy) {
                l.isDragging = false
                l.snapPreview = nil
            }
            if let side = notchSide {
                let nl = m.notchLayout(notch: notch, side: side, in: vf)
                withAnimation(Theme.morph) {
                    scene.origin = nl.windowOrigin
                    l.edge = .top
                    l.notchWing = nl.wing
                    l.notchSide = side
                }
            } else if let edge = EdgeSnapper.nearestEdge(card: card, in: vf, threshold: 36) {
                withAnimation(Theme.morph) {
                    scene.origin = m.windowOrigin(docked: edge, along: m.along(card: card, edge: edge, in: vf), in: vf)
                    l.edge = edge
                }
            }
        }

        @MainActor func collapse() {
            withAnimation(Theme.morph) {
                l.isHovering = false
                l.isExpanded = false
            }
        }

        /// Pointer position over the collapsed tab / wing, in scene coordinates.
        @MainActor func tabCenter() -> CGPoint {
            let r = l.notchWing != nil ? (l.wingRect ?? .zero) : l.tabRect
            let size = m.windowSize
            return CGPoint(x: scene.origin.x + r.midX, y: scene.origin.y + size.height - r.midY)
        }

        // Floating, then drag to the right edge.
        run(0.5)
        pickUp()
        run(0.12)
        drag(to: CGPoint(x: vf.maxX - 395 + grab.x, y: 250 + grab.y), arc: 50, 1.1)
        drop()
        run(0.45)
        point(to: CGPoint(x: scene.cursor.x - 280, y: scene.cursor.y - 120), 0.4)
        collapse()
        run(0.55)

        // Grab the tab and slide it down the edge.
        point(to: tabCenter(), 0.45)
        pickUp()
        run(0.15)
        // Straight down: the card stays on the edge the whole way.
        drag(to: CGPoint(x: scene.cursor.x, y: scene.cursor.y - 250), arc: 0, 1.0)
        drop()
        run(0.4)
        point(to: CGPoint(x: scene.cursor.x - 260, y: scene.cursor.y + 90), 0.35)
        collapse()
        run(0.5)

        // Up to the notch.
        point(to: tabCenter(), 0.45)
        pickUp()
        run(0.15)
        drag(to: CGPoint(x: size.width / 2 + 80, y: vf.maxY - 20), arc: 40, 1.25)
        drop(notchSide: .right)
        run(0.35)
        point(to: CGPoint(x: scene.cursor.x + 60, y: scene.cursor.y - 200), 0.35)
        collapse()
        run(0.5)
        // Hover the wing: the card drops down under the notch.
        point(to: tabCenter(), 0.45)
        withAnimation(Theme.snappy) { l.isHovering = true }
        run(0.1)
        withAnimation(Theme.morph) { l.isExpanded = true }
        run(0.9)

        // Across to the left edge.
        point(to: CGPoint(x: scene.origin.x + l.cardRect.minX + grab.x, y: scene.origin.y + m.windowSize.height - l.cardRect.maxY + grab.y), 0.3)
        pickUp()
        run(0.12)
        drag(to: CGPoint(x: 20 + grab.x, y: 300 + grab.y), arc: 60, 1.2)
        drop()
        run(0.4)
        point(to: CGPoint(x: scene.cursor.x + 300, y: scene.cursor.y - 60), 0.4)
        collapse()
        run(0.8)
        stage.close()

        let virtualTime = Theme.playbackDate(Date()).timeIntervalSince(virtualStart)
        try! String(format: "%.2f", Double(frameCount) / virtualTime).write(to: out.appendingPathComponent("drag-fps.txt"), atomically: true, encoding: .utf8)
        _ = slow
        Theme.slowdown = 1
    }
}
