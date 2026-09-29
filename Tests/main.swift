import Foundation

// Minimal test runner: SwiftPM/XCTest aren't usable with the installed Command Line Tools,
// so scripts/test.sh compiles the pure-logic sources together with this file.

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(URL(fileURLWithPath: file).lastPathComponent):\(line) \(message)")
    }
}

func close(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.001) -> Bool { abs(a - b) < eps }

let m = OverlayMetrics()
let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
func card(x: CGFloat, y: CGFloat) -> CGRect { CGRect(origin: CGPoint(x: x, y: y), size: m.cardSize) }

// MARK: nearestEdge

check(EdgeSnapper.nearestEdge(card: card(x: 10, y: 400), in: vf, threshold: 28) == .left, "near left")
check(EdgeSnapper.nearestEdge(card: card(x: vf.maxX - m.cardSize.width - 5, y: 400), in: vf, threshold: 28) == .right, "near right")
check(EdgeSnapper.nearestEdge(card: card(x: 500, y: vf.maxY - m.cardSize.height - 3), in: vf, threshold: 28) == .top, "near top")
check(EdgeSnapper.nearestEdge(card: card(x: 500, y: 2), in: vf, threshold: 28) == .bottom, "near bottom")
check(EdgeSnapper.nearestEdge(card: card(x: 500, y: 400), in: vf, threshold: 28) == nil, "center: no edge")
check(EdgeSnapper.nearestEdge(card: card(x: 40, y: 400), in: vf, threshold: 28) == nil, "just outside threshold")
check(EdgeSnapper.nearestEdge(card: card(x: -30, y: 400), in: vf, threshold: 28) == .left, "past edge still snaps")
// Corner: top is closer, but side edges win.
check(EdgeSnapper.nearestEdge(card: card(x: 20, y: vf.maxY - m.cardSize.height - 2), in: vf, threshold: 28) == .left, "corner prefers side")

// MARK: decide

let screens = [screen]
if case .dock(.left, let along) = EdgeSnapper.decide(card: card(x: 5, y: vf.maxY - m.cardSize.height), visibleFrame: vf, screens: screens, threshold: 28, magnet: true, metrics: m) {
    check(close(along, 1), "top-left corner along == 1, got \(along)")
} else {
    check(false, "corner docks left")
}
check(EdgeSnapper.decide(card: card(x: 5, y: 400), visibleFrame: vf, screens: screens, threshold: 28, magnet: false, metrics: m) == .float, "magnet off floats")
let nearCenterTop = card(x: vf.midX - m.cardSize.width / 2 + 30, y: vf.maxY - m.cardSize.height - 4)
check(EdgeSnapper.decide(card: nearCenterTop, visibleFrame: vf, screens: screens, threshold: 28, magnet: true, metrics: m) == .dock(.top, along: 0.5), "center detent on top edge")
let offCenterTop = card(x: 200, y: vf.maxY - m.cardSize.height - 4)
check(EdgeSnapper.decide(card: offCenterTop, visibleFrame: vf, screens: screens, threshold: 28, magnet: true, metrics: m) != .dock(.top, along: 0.5), "no detent far from center")
check(EdgeSnapper.decide(card: card(x: -250, y: 400), visibleFrame: vf, screens: screens, threshold: 28, magnet: true, metrics: m) == .dismiss, "mostly off-screen dismisses")
check(EdgeSnapper.decide(card: card(x: -100, y: 400), visibleFrame: vf, screens: screens, threshold: 28, magnet: true, metrics: m) != .dismiss, "partly off-screen docks")
// Card straddling two screens is not off-screen.
let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
check(close(EdgeSnapper.offscreenFraction(card: card(x: 1300, y: 400), screens: [screen, second]), 0), "straddling two screens is fully visible")

// MARK: windowOrigin round-trip

for edge in DockEdge.allCases {
    for along: CGFloat in [0, 0.3, 1] {
        let origin = m.windowOrigin(docked: edge, along: along, in: vf)
        let local = m.cardRect(docked: edge)
        // Convert SwiftUI (top-left) local rect to screen coords.
        let cardScreen = CGRect(x: origin.x + local.minX, y: origin.y + m.windowSize.height - local.maxY, width: local.width, height: local.height)
        check(cardScreen.minX >= vf.minX - 0.001 && cardScreen.maxX <= vf.maxX + 0.001, "\(edge) \(along): card inside horizontally")
        check(cardScreen.minY >= vf.minY - 0.001 && cardScreen.maxY <= vf.maxY + 0.001, "\(edge) \(along): card inside vertically")
        let d = Dictionary(uniqueKeysWithValues: EdgeSnapper.distances(card: cardScreen, in: vf).map { ($0.0, $0.1) })
        check(close(d[edge]!, m.dockGap), "\(edge): card sits dockGap from its edge, got \(d[edge]!)")
        check(close(m.along(card: cardScreen, edge: edge, in: vf), along), "\(edge): along round-trips")
    }
}

// Tab sits flush against its edge and never crosses it (top: never onto the menu bar).
func tabScreen(_ edge: DockEdge, extra: CGFloat = 0) -> CGRect {
    let o = m.windowOrigin(docked: edge, along: 0.5, in: vf)
    let t = m.tabRect(docked: edge, extra: extra)
    return CGRect(x: o.x + t.minX, y: o.y + m.windowSize.height - t.maxY, width: t.width, height: t.height)
}
check(close(tabScreen(.left).minX, vf.minX), "left tab flush")
check(close(tabScreen(.right).maxX, vf.maxX), "right tab flush")
check(close(tabScreen(.top).maxY, vf.maxY), "top tab flush under menu bar")
check(close(tabScreen(.bottom).minY, vf.minY), "bottom tab flush")
check(close(tabScreen(.top, extra: 14).maxY, vf.maxY), "peeking top tab grows downward only")
check(close(tabScreen(.top).midX, vf.midX), "centered top tab is centered on screen")

// MARK: notch

do {
    // Built-in 14" MacBook Pro: notch 663.5...848.5, menu bar 32pt.
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let dock = CGRect(x: 0, y: 0, width: 1512, height: 950)
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
    for side in [NotchSide.left, .right] {
        let l = m.notchLayout(notch: notch, side: side, in: dock)
        check(close(l.wingScreen.maxY, frame.maxY) && close(l.wingScreen.minY, dock.maxY), "\(side): wing fills the menu bar row")
        let visible = l.wingScreen.width - m.wingOverlap
        if side == .right {
            check(close(l.wingScreen.minX, notch.maxX - m.wingOverlap), "right wing tucks under the notch")
        } else {
            check(close(l.wingScreen.maxX, notch.minX + m.wingOverlap), "left wing tucks under the notch")
        }
        check(close(visible, m.wingWidth), "\(side): visible wing width")
        // Local wing rect maps back to the same screen rect.
        let top = l.windowOrigin.y + m.windowSize.height
        check(l.wing.minY >= 0 && close(top - l.wing.minY, l.wingScreen.maxY), "\(side): wing inside window, local↔screen")
        check(close(top, frame.maxY), "\(side): window doesn't cross the screen top onto a display above")
        check(close(l.wing.minY, 0), "\(side): wing at the window's top")
        // Card hangs from the wing's bottom (see OverlayLayout.cardRect).
        check(close(top - l.wing.maxY, notch.minY), "\(side): card starts at the bottom of the notch row")
        check(l.wing.maxY + m.cardSize.height <= m.windowSize.height, "\(side): card fits in the window")
        check(close(l.windowOrigin.x + l.wing.minX, l.wingScreen.minX), "\(side): wing x maps")
    }
}

// MARK: scale

do {
    var big = OverlayMetrics()
    big.scale = 1.3
    check(big.cardSize.width > m.cardSize.width && big.windowSize.width == big.cardSize.width + 2 * big.padding, "scale grows card and window")
    check(OverlayMetrics.scale(forCardWidth: 10_000) == OverlayMetrics.scaleRange.upperBound, "scale capped at max")
    check(OverlayMetrics.scale(forCardWidth: 10) == OverlayMetrics.scaleRange.lowerBound, "scale floored at min")
    let o = big.windowOrigin(docked: .right, along: 0.5, in: vf)
    let c = big.cardRect(docked: .right)
    check(close(o.x + c.maxX, vf.maxX - big.dockGap), "scaled card still docks dockGap from the edge")
}

// MARK: floating

let clamped = m.clampedFloatingOrigin(CGPoint(x: -500, y: 5000), in: vf)
let cc = m.floatingCard(windowOrigin: clamped)
check(close(cc.minX, vf.minX) && close(cc.maxY, vf.maxY), "clamp keeps card on screen")
let r = m.floatingRatio(windowOrigin: m.floatingOrigin(ratio: CGPoint(x: 0.25, y: 0.75), in: vf), in: vf)
check(close(r.x, 0.25) && close(r.y, 0.75), "floating ratio round-trips")

// MARK: magnet

let far = EdgeSnapper.magnetOffset(card: card(x: 300, y: 400), in: vf, threshold: 28, gap: 10)
check(far.dx == 0 && far.dy == 0, "no pull far away")
let near = EdgeSnapper.magnetOffset(card: card(x: 10 + 7, y: 400), in: vf, threshold: 28, gap: 10)
check(near.dx < 0 && near.dx > -7, "pulls toward left edge without overshooting, got \(near.dx)")
let edgeish = EdgeSnapper.magnetOffset(card: card(x: 10 + 27.9, y: 400), in: vf, threshold: 28, gap: 10)
check(abs(edgeish.dx) < 0.5, "pull fades to zero at threshold")

// MARK: RouterLogic

let t0 = Date(timeIntervalSince1970: 1000)
func np(_ bid: String, _ title: String, playing: Bool = true) -> NowPlaying {
    NowPlaying(bundleID: bid, title: title, artist: "A", album: "B", duration: 200, elapsed: 10, timestamp: t0, isPlaying: playing, artworkKey: title)
}
let spotify = "com.spotify.client", music = "com.apple.Music", chrome = "com.google.Chrome"
let scriptableApps: Set = [spotify, music]

var res = RouterLogic.resolve(system: np(chrome, "Video"), scriptable: [:], scriptableApps: scriptableApps, pinned: nil, lastSeen: [:], now: t0)
check(res.nowPlaying?.title == "Video" && res.target == .system && res.status == .ok, "auto follows system")

res = RouterLogic.resolve(system: nil, scriptable: [:], scriptableApps: scriptableApps, pinned: nil, lastSeen: [:], now: t0)
check(res == .idle, "auto idle")

// The user's scenario: pinned to Spotify, browser starts playing.
res = RouterLogic.resolve(system: np(chrome, "Video"), scriptable: [spotify: .running(np(spotify, "Song", playing: false))], scriptableApps: scriptableApps, pinned: spotify, lastSeen: [:], now: t0)
check(res.nowPlaying?.title == "Song" && res.target == .scriptable(spotify), "pinned Spotify ignores browser")

res = RouterLogic.resolve(system: nil, scriptable: [:], scriptableApps: scriptableApps, pinned: spotify, lastSeen: [spotify: np(spotify, "Old")], now: t0.addingTimeInterval(5))
check(res.status == .notRunning(spotify) && res.target == .none, "pinned app not running")
check(res.nowPlaying?.title == "Old" && res.nowPlaying?.isPlaying == false, "shows last track paused")
check(close(CGFloat(res.nowPlaying!.elapsed), 15), "last track frozen at its live position")

res = RouterLogic.resolve(system: nil, scriptable: [spotify: .denied], scriptableApps: scriptableApps, pinned: spotify, lastSeen: [:], now: t0)
check(res.status == .noPermission(spotify), "automation denied")

res = RouterLogic.resolve(system: nil, scriptable: [music: .running(nil)], scriptableApps: scriptableApps, pinned: music, lastSeen: [:], now: t0)
check(res.status == .pinnedIdle(music) && res.target == .scriptable(music), "pinned idle still controllable")

res = RouterLogic.resolve(system: np(chrome, "Video"), scriptable: [:], scriptableApps: scriptableApps, pinned: chrome, lastSeen: [:], now: t0)
check(res.target == .system && res.status == .ok, "pinned non-scriptable while current")

res = RouterLogic.resolve(system: np(spotify, "Song"), scriptable: [:], scriptableApps: scriptableApps, pinned: chrome, lastSeen: [chrome: np(chrome, "Video")], now: t0)
check(res.target == .none && res.status == .notCurrent(chrome) && res.nowPlaying?.title == "Video", "pinned non-scriptable not current")

// MARK: NowPlaying

let p = np(spotify, "S")
check(close(CGFloat(p.elapsed(at: t0.addingTimeInterval(3))), 13), "elapsed advances while playing")
check(close(CGFloat(p.elapsed(at: t0.addingTimeInterval(9999))), 200), "elapsed clamps to duration")
check(close(CGFloat(np(spotify, "S", playing: false).elapsed(at: t0.addingTimeInterval(3))), 10), "paused doesn't advance")
check(formatTime(65) == "1:05" && formatTime(3725) == "1:02:05", "formatTime")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
