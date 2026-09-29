import CoreGraphics

/// A screen edge the overlay can dock to.
enum DockEdge: String, Codable, CaseIterable {
    case left, right, top, bottom

    /// Side edges (left/right) run vertically; the tab stacks its content vertically there.
    var isSide: Bool { self == .left || self == .right }
}

/// Fixed geometry of the overlay window and the shapes drawn inside it.
///
/// The window is always `cardSize + 2 * padding`. The padding holds the shadow; when docked,
/// the padding on the edge side lies past the edge (off-screen, or over the menu bar for the
/// top edge), and nothing interactive is drawn there, so the tab sits flush against the edge.
struct OverlayMetrics: Equatable {
    static let baseCardSize = CGSize(width: 380, height: 168)
    static let scaleRange: ClosedRange<CGFloat> = 0.8...1.35
    /// Player size; the card and everything in it scale together.
    var scale: CGFloat = 1
    var cardSize: CGSize {
        CGSize(width: (Self.baseCardSize.width * scale).rounded(), height: (Self.baseCardSize.height * scale).rounded())
    }
    var tabThickness: CGFloat = 40
    var tabLength: CGFloat = 112
    /// Also tall enough, above a top-docked card, to hold the menu bar row for the notch wing.
    var padding: CGFloat = 40
    var dockGap: CGFloat = 10
    /// Width of the notch wing's visible part, and how far it tucks under the notch.
    var wingWidth: CGFloat = 78
    var wingOverlap: CGFloat = 12

    var windowSize: CGSize {
        CGSize(width: cardSize.width + padding * 2, height: cardSize.height + padding * 2)
    }

    /// Card rect in window-local, top-left-origin (SwiftUI) coordinates.
    func cardRect(docked edge: DockEdge?) -> CGRect {
        var r = CGRect(origin: CGPoint(x: padding, y: padding), size: cardSize)
        switch edge {
        case .left?: r.origin.x += dockGap
        case .right?: r.origin.x -= dockGap
        case .top?: r.origin.y += dockGap
        case .bottom?: r.origin.y -= dockGap
        case nil: break
        }
        return r
    }

    /// Tab rect in SwiftUI coordinates, flush against the docked edge.
    /// `extra` grows it away from the edge (hover swell, new-track peek).
    func tabRect(docked edge: DockEdge, extra: CGFloat = 0) -> CGRect {
        let s = windowSize, p = padding, t = tabThickness + extra
        switch edge {
        case .left:
            return CGRect(x: p, y: (s.height - tabLength) / 2, width: t, height: tabLength)
        case .right:
            return CGRect(x: s.width - p - t, y: (s.height - tabLength) / 2, width: t, height: tabLength)
        case .top:
            return CGRect(x: (s.width - tabLength) / 2, y: p, width: tabLength, height: t)
        case .bottom:
            return CGRect(x: (s.width - tabLength) / 2, y: s.height - p - t, width: tabLength, height: t)
        }
    }

    /// Layout for attaching beside the notch. `notch` is the notch rect in screen coordinates
    /// (between the auxiliary top areas, down to the menu bar bottom); `vf` is the docking frame
    /// below the menu bar. The card hangs below the menu bar, centered under notch + wing.
    func notchLayout(notch: CGRect, side: NotchSide, in vf: CGRect) -> (windowOrigin: CGPoint, wing: CGRect, wingScreen: CGRect) {
        let wingScreen = side == .right
            ? CGRect(x: notch.maxX - wingOverlap, y: notch.minY, width: wingWidth + wingOverlap, height: notch.height)
            : CGRect(x: notch.minX - wingWidth, y: notch.minY, width: wingWidth + wingOverlap, height: notch.height)
        let group = notch.union(wingScreen)
        let cardMinX = (group.midX - cardSize.width / 2).clamped(to: vf.minX...max(vf.minX, vf.maxX - cardSize.width))
        let span = vf.width - cardSize.width
        let along = span > 0 ? (cardMinX - vf.minX) / span : 0.5
        // Top of the window exactly at the top of the screen: nothing may cross onto a display
        // above (with per-display Spaces, macOS can then assign the window to the wrong display).
        let origin = CGPoint(x: windowOrigin(docked: .top, along: along, in: vf).x, y: notch.maxY - windowSize.height)
        let windowTop = origin.y + windowSize.height
        let wing = CGRect(x: wingScreen.minX - origin.x, y: windowTop - wingScreen.maxY, width: wingScreen.width, height: wingScreen.height)
        return (origin, wing, wingScreen)
    }

    /// Window origin (AppKit, bottom-left) that docks the card to `edge` of `vf`.
    /// `along` is 0...1 along the edge: bottom→top for side edges, left→right for top/bottom.
    func windowOrigin(docked edge: DockEdge, along: CGFloat, in vf: CGRect) -> CGPoint {
        let s = windowSize, p = padding, r = along.clamped(to: 0...1)
        switch edge {
        case .left, .right:
            let cardMinY = vf.minY + max(vf.height - cardSize.height, 0) * r
            let x = edge == .left ? vf.minX - p : vf.maxX + p - s.width
            return CGPoint(x: x, y: cardMinY - p)
        case .top, .bottom:
            let cardMinX = vf.minX + max(vf.width - cardSize.width, 0) * r
            let y = edge == .bottom ? vf.minY - p : vf.maxY + p - s.height
            return CGPoint(x: cardMinX - p, y: y)
        }
    }

    /// Scale that makes the card `width` wide, within the allowed range.
    static func scale(forCardWidth width: CGFloat) -> CGFloat {
        (width / baseCardSize.width).clamped(to: scaleRange)
    }

    /// Position of a card along `edge`, as the 0...1 ratio `windowOrigin(docked:along:in:)` takes.
    func along(card: CGRect, edge: DockEdge, in vf: CGRect) -> CGFloat {
        if edge.isSide {
            let span = vf.height - card.height
            return span > 0 ? ((card.minY - vf.minY) / span).clamped(to: 0...1) : 0.5
        }
        let span = vf.width - card.width
        return span > 0 ? ((card.minX - vf.minX) / span).clamped(to: 0...1) : 0.5
    }

    /// Card rect in screen coordinates for an undocked window at `origin`.
    func floatingCard(windowOrigin origin: CGPoint) -> CGRect {
        CGRect(origin: CGPoint(x: origin.x + padding, y: origin.y + padding), size: cardSize)
    }

    /// Window origin that keeps an undocked card fully inside `vf`.
    func clampedFloatingOrigin(_ origin: CGPoint, in vf: CGRect) -> CGPoint {
        let card = floatingCard(windowOrigin: origin)
        let x = card.minX.clamped(to: vf.minX...max(vf.minX, vf.maxX - card.width))
        let y = card.minY.clamped(to: vf.minY...max(vf.minY, vf.maxY - card.height))
        return CGPoint(x: x - padding, y: y - padding)
    }

    /// Card position inside `vf` as 0...1 ratios, so it survives resolution changes.
    func floatingRatio(windowOrigin origin: CGPoint, in vf: CGRect) -> CGPoint {
        let card = floatingCard(windowOrigin: origin)
        let sx = vf.width - card.width, sy = vf.height - card.height
        return CGPoint(
            x: sx > 0 ? ((card.minX - vf.minX) / sx).clamped(to: 0...1) : 0.5,
            y: sy > 0 ? ((card.minY - vf.minY) / sy).clamped(to: 0...1) : 0.5
        )
    }

    func floatingOrigin(ratio: CGPoint, in vf: CGRect) -> CGPoint {
        let x = vf.minX + max(vf.width - cardSize.width, 0) * ratio.x.clamped(to: 0...1)
        let y = vf.minY + max(vf.height - cardSize.height, 0) * ratio.y.clamped(to: 0...1)
        return CGPoint(x: x - padding, y: y - padding)
    }
}

enum NotchSide: String, Codable {
    case left, right
}

enum SnapDecision: Equatable {
    case dock(DockEdge, along: CGFloat)
    case float
    case dismiss
}

/// Pure snapping math. All rects are AppKit screen coordinates.
enum EdgeSnapper {
    /// Signed distance from the card to each edge of `vf`; negative when past the edge.
    static func distances(card: CGRect, in vf: CGRect) -> [(DockEdge, CGFloat)] {
        [
            (.left, card.minX - vf.minX),
            (.right, vf.maxX - card.maxX),
            (.bottom, card.minY - vf.minY),
            (.top, vf.maxY - card.maxY),
        ]
    }

    /// The edge the card would dock to, or nil if none is within `threshold`.
    /// Side edges win over top/bottom, so a card near a corner docks to the side, in the corner.
    static func nearestEdge(card: CGRect, in vf: CGRect, threshold: CGFloat) -> DockEdge? {
        let near = distances(card: card, in: vf).filter { $0.1 <= threshold }
        let sides = near.filter { $0.0.isSide }
        let pool = sides.isEmpty ? near : sides
        return pool.min { $0.1 < $1.1 }?.0
    }

    /// Fraction of the card not on any screen.
    static func offscreenFraction(card: CGRect, screens: [CGRect]) -> CGFloat {
        let area = card.width * card.height
        guard area > 0 else { return 0 }
        let visible = screens.reduce(CGFloat(0)) { sum, screen in
            let i = card.intersection(screen)
            return sum + (i.isNull ? 0 : i.width * i.height)
        }
        return (1 - visible / area).clamped(to: 0...1)
    }

    static func decide(
        card: CGRect, visibleFrame vf: CGRect, screens: [CGRect],
        threshold: CGFloat, magnet: Bool, metrics: OverlayMetrics
    ) -> SnapDecision {
        if offscreenFraction(card: card, screens: screens) > 0.5 { return .dismiss }
        if magnet, let edge = nearestEdge(card: card, in: vf, threshold: threshold) {
            var along = metrics.along(card: card, edge: edge, in: vf)
            // Center detent: dropped near the middle of an edge, it lands exactly centered.
            let offCenter = edge.isSide ? card.midY - vf.midY : card.midX - vf.midX
            if abs(offCenter) < threshold * 1.5 { along = 0.5 }
            return .dock(edge, along: along)
        }
        return .float
    }

    /// Magnetic pull while dragging: the closer to an edge, the harder the card is drawn to it.
    /// Returns the offset to add to the raw drag position. Continuous at `threshold`.
    static func magnetOffset(card: CGRect, in vf: CGRect, threshold: CGFloat, gap: CGFloat) -> CGVector {
        var dx: CGFloat = 0, dy: CGFloat = 0
        for (edge, raw) in distances(card: card, in: vf) {
            let d = raw - gap
            guard d > 0, d < threshold else { continue }
            let pulled = d * pow(d / threshold, 2)
            let delta = d - pulled
            switch edge {
            case .left: if dx == 0 { dx = -delta }
            case .right: if dx == 0 { dx = delta }
            case .bottom: if dy == 0 { dy = -delta }
            case .top: if dy == 0 { dy = delta }
            }
        }
        return CGVector(dx: dx, dy: dy)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
