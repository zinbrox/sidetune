import AppKit
import QuartzCore
import SwiftUI

/// Borderless, non-activating, always-on-top panel. Never becomes key, so it never
/// steals focus or keystrokes from the app you're using.
final class OverlayPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    func applyLevel(overFullScreen: Bool) {
        // One above status-bar level, so other apps' status-level panels can't cover it.
        level = overFullScreen ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
        collectionBehavior = overFullScreen
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            : [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Let the docked window hang past the screen edge.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Clicks work on the first press even though the panel is never key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Damped spring for window position, stepped on the display's refresh.
@MainActor
final class WindowSpring: NSObject {
    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private var position = CGPoint.zero
    private var velocity = CGVector.zero
    private var target = CGPoint.zero
    private var lastTime: CFTimeInterval = 0
    private var completion: (() -> Void)?
    /// Highest origin.y allowed mid-flight; overshoot is absorbed instead of crossing it.
    private var ceiling: CGFloat?

    /// Slightly under-damped (critical ≈ 33) for a small, soft overshoot.
    var stiffness: CGFloat = 280
    var damping: CGFloat = 25

    var isAnimating: Bool { link != nil }

    init(window: NSWindow) { self.window = window }

    func animate(to target: CGPoint, velocity: CGVector = .zero, ceiling: CGFloat? = nil, completion: (() -> Void)? = nil) {
        guard let window, let view = window.contentView else { return }
        if Theme.reduceMotion {
            stop()
            window.setFrameOrigin(target)
            completion?()
            return
        }
        position = window.frame.origin
        // Cap fling speed so a hard throw doesn't wildly overshoot.
        let speed = hypot(velocity.dx, velocity.dy), cap: CGFloat = 4000
        self.velocity = speed > cap ? CGVector(dx: velocity.dx * cap / speed, dy: velocity.dy * cap / speed) : velocity
        self.target = target
        self.ceiling = ceiling
        self.completion = completion
        lastTime = CACurrentMediaTime()
        if link == nil {
            let l = view.displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        completion = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let window else { return stop() }
        let now = CACurrentMediaTime()
        var remaining = min(now - lastTime, 1.0 / 30)
        lastTime = now
        let h: CGFloat = 1.0 / 480
        while remaining > 0 {
            let dt = CGFloat(min(h, remaining))
            let ax = -stiffness * (position.x - target.x) - damping * velocity.dx
            let ay = -stiffness * (position.y - target.y) - damping * velocity.dy
            velocity.dx += ax * dt
            velocity.dy += ay * dt
            position.x += velocity.dx * dt
            position.y += velocity.dy * dt
            if let ceiling, position.y > ceiling {
                position.y = ceiling
                velocity.dy = min(velocity.dy, 0)
            }
            remaining -= Double(dt)
        }
        let settled = hypot(position.x - target.x, position.y - target.y) < 0.4 && hypot(velocity.dx, velocity.dy) < 4
        window.setFrameOrigin(settled ? target : position)
        if settled {
            let done = completion
            stop()
            done?()
        }
    }
}
