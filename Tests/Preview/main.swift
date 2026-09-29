import AppKit
import SwiftUI

// Renders the overlay states to PNGs with sample data, for visual review without touching the live app.
MainActor.assumeIsolated {
    let out = URL(fileURLWithPath: CommandLine.arguments[1])
    let art = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    _ = NSApplication.shared
    let settings = Settings()
    let router = MediaRouter(settings: settings)
    let np = NowPlaying(bundleID: "com.spotify.client", title: "Midnight City (Extended Mix) — Live at the Hollywood Bowl", artist: "M83",
                        album: "Hurry Up, We're Dreaming", duration: 244, elapsed: 97, timestamp: Date(), isPlaying: true, artwork: art, artworkKey: "a", shuffle: true, repeatMode: .off)
    router.previewSet(Resolution(nowPlaying: np, target: .scriptable("com.spotify.client"), status: .ok))

    func snap<V: View>(_ view: V, _ size: CGSize, _ name: String) {
        // On screen (offscreen windows can't be captured) but at desktop level, behind everything.
        let origin = NSScreen.screens[0].visibleFrame.origin
        let window = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.backgroundColor = NSColor(calibratedRed: 0.35, green: 0.4, blue: 0.5, alpha: 1)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        // screencapture composites CoreAnimation filters (blur), which cacheDisplay skips.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(window.windowNumber), out.appendingPathComponent(name + ".png").path]
        try! p.run()
        p.waitUntilExit()
        window.orderOut(nil)
    }

    let actions = OverlayActions(dragChanged: {}, dragEnded: {}, expand: {}, close: {}, sourceMenu: {})
    for (name, edge, peek, tilt) in [("tab-peek", DockEdge.right, true, 0.0), ("card-drag-tilt", nil as DockEdge?, false, 4.0)] {
        let layout = OverlayLayout()
        layout.edge = edge
        layout.isExpanded = edge == nil
        layout.isVisible = true
        layout.isPeeking = peek
        layout.isDragging = tilt != 0
        layout.dragTilt = tilt
        snap(OverlayRootView(layout: layout, router: router, settings: settings, actions: actions), layout.metrics.windowSize, name)
    }
    for (name, scale) in [("size-min", OverlayMetrics.scaleRange.lowerBound), ("size-max", OverlayMetrics.scaleRange.upperBound)] {
        let layout = OverlayLayout()
        layout.metrics.scale = scale
        layout.isVisible = true
        layout.isHovering = true
        snap(OverlayRootView(layout: layout, router: router, settings: settings, actions: actions), layout.metrics.windowSize, name)
    }
    for (name, expanded) in [("notch-collapsed", false), ("notch-expanded", true)] {
        let layout = OverlayLayout()
        let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
        layout.edge = .top
        layout.notchWing = layout.metrics.notchLayout(notch: notch, side: .right, in: CGRect(x: 0, y: 0, width: 1512, height: 949)).wing
        layout.isExpanded = expanded
        layout.isHovering = expanded
        layout.isVisible = true
        snap(OverlayRootView(layout: layout, router: router, settings: settings, actions: actions), layout.metrics.windowSize, name)
    }
    for (name, edge, expanded, hovering, preview) in [
        ("card-floating", nil as DockEdge?, true, true, nil as DockEdge?),
        ("card-docked-right", .right, true, true, nil),
        ("tab-right", .right, false, false, nil),
        ("tab-bottom", .bottom, false, false, nil),
        ("tab-top", .top, false, false, nil),
        ("card-docked-top", .top, true, true, nil),
        ("card-snap-preview", nil, true, true, .left),
    ] {
        let layout = OverlayLayout()
        layout.edge = edge
        layout.isExpanded = expanded
        layout.isHovering = hovering
        layout.isVisible = true
        layout.snapPreview = preview
        snap(OverlayRootView(layout: layout, router: router, settings: settings, actions: actions), layout.metrics.windowSize, name)
    }
    snap(MiniPlayer(router: router, settings: settings, showSourceMenu: {}, openSettings: {}), CGSize(width: 300, height: 230), "mini")

    router.previewSet(Resolution(nowPlaying: nil, target: .none, status: .notRunning("com.spotify.client")))
    let layout = OverlayLayout(); layout.isVisible = true; layout.isHovering = true
    snap(OverlayRootView(layout: layout, router: router, settings: settings, actions: actions), layout.metrics.windowSize, "card-not-running")
}
