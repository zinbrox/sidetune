import AppKit
import Combine
import SwiftUI

/// Where the overlay lives, stored relative to the screen so it survives resolution changes.
enum Placement: Codable, Equatable {
    case docked(edge: DockEdge, along: CGFloat, screen: UInt32?)
    case floating(x: CGFloat, y: CGFloat, screen: UInt32?)
    /// Beside the notch, in the menu bar row; the card drops down below the menu bar.
    case notch(side: NotchSide, screen: UInt32?)

    static let `default` = Placement.docked(edge: .right, along: 0.62, screen: nil)
}

/// View state the SwiftUI side renders. Changes are made inside `withAnimation` by the controller.
@MainActor
final class OverlayLayout: ObservableObject {
    @Published var metrics = OverlayMetrics()
    @Published var isResizing = false
    @Published var edge: DockEdge?
    @Published var isExpanded = true
    @Published var isVisible = false
    @Published var isHovering = false
    @Published var isDragging = false
    @Published var snapPreview: DockEdge?
    /// Collapsed tab briefly pops out when a new track starts.
    @Published var isPeeking = false
    /// Sway while dragging, in degrees, from horizontal drag speed.
    @Published var dragTilt: Double = 0
    /// Local rect of the notch wing when attached beside the notch (edge is then `.top`).
    @Published var notchWing: CGRect?
    @Published var notchSide: NotchSide = .right
    /// Offset of all content inside the window (SwiftUI space). The window is kept inside its
    /// screen; when the ideal frame would cross the screen edge, the window is clamped and the
    /// content shifted back, so it lands in the same place on screen.
    @Published var contentShift: CGSize = .zero

    /// Expanded whenever it isn't docked; docked cards collapse into a tab.
    var showsCard: Bool { edge == nil || isExpanded }

    /// Tab rect including hover swell and peek.
    var tabRect: CGRect {
        metrics.tabRect(docked: edge ?? .right, extra: isPeeking ? 14 : (isHovering && !isExpanded ? 5 : 0))
    }

    /// Card corner holding the resize grip: the bottom corner away from the docked edge
    /// (top corner when docked at the bottom). The opposite corner stays put while resizing.
    var resizeCorner: (right: Bool, bottom: Bool) {
        switch edge {
        case .right?: return (false, true)
        case .bottom?: return (true, false)
        default: return (true, true)
        }
    }

    /// Wing rect including peek, which grows it outward, away from the notch.
    var wingRect: CGRect? {
        guard var r = notchWing else { return nil }
        let extra: CGFloat = isPeeking ? 12 : (isHovering && !isExpanded ? 4 : 0)
        r.size.width += extra
        if notchSide == .left { r.origin.x -= extra }
        return r
    }

    /// Card rect, in window-local coordinates. Beside the notch it hangs directly from the
    /// notch row with no gap, so notch, wing and card read as one piece.
    var cardRect: CGRect {
        var r = metrics.cardRect(docked: edge)
        if let wing = notchWing { r.origin.y = wing.maxY }
        return r
    }

    /// Regions that should receive the mouse, in window-local SwiftUI coordinates.
    var interactiveRects: [CGRect] {
        guard let edge else { return [metrics.cardRect(docked: nil)] }
        let card = cardRect
        if let wing = wingRect {
            guard isExpanded else { return [wing] }
            // Wing plus a bridge straight down to the card, so moving from the wing to the card
            // keeps it open, without claiming the rest of the menu bar above the card.
            let bridge = CGRect(x: wing.minX, y: wing.minY, width: wing.width, height: card.minY - wing.minY)
            return [card, bridge]
        }
        // When expanded, include the tab strip too so the gap between screen edge and card
        // doesn't count as "left the card" and collapse it under the cursor.
        return isExpanded ? [card.union(tabRect)] : [tabRect]
    }
}

@MainActor
final class OverlayController {
    let layout = OverlayLayout()
    private let panel: OverlayPanel
    private let settings: Settings
    private let router: MediaRouter
    private lazy var spring = WindowSpring(window: panel)
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []

    private var placement: Placement {
        didSet { if let data = try? JSONEncoder().encode(placement) { UserDefaults.standard.set(data, forKey: "placement") } }
    }

    // Drag state
    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero
    private var dragSamples: [(t: CFTimeInterval, p: CGPoint)] = []
    private var placementBeforeDrag: Placement?

    // Resize state
    private var resizeStartMouse = CGPoint.zero
    private var resizeStartWidth: CGFloat = 0
    private var resizeAnchor = CGPoint.zero

    private var hoverTask: DispatchWorkItem?
    private var peekTask: DispatchWorkItem?
    private var tiltTask: DispatchWorkItem?
    private var idleTask: DispatchWorkItem?
    private var hoverPoll: Timer?
    private var autoHidden = false

    var onShowSourceMenu: (() -> Void)?

    init(settings: Settings, router: MediaRouter) {
        self.settings = settings
        self.router = router
        if let data = UserDefaults.standard.data(forKey: "placement"),
           let saved = try? JSONDecoder().decode(Placement.self, from: data) {
            placement = saved
        } else {
            placement = .default
        }
        layout.metrics.scale = CGFloat(settings.cardScale).clamped(to: OverlayMetrics.scaleRange)
        panel = OverlayPanel(size: layout.metrics.windowSize)
        panel.applyLevel(overFullScreen: settings.overFullScreen)

        let root = OverlayRootView(
            layout: layout, router: router, settings: settings,
            actions: OverlayActions(
                dragChanged: { [weak self] in self?.dragChanged() },
                dragEnded: { [weak self] in self?.dragEnded() },
                expand: { [weak self] in self?.setExpanded(true) },
                close: { [weak self] in self?.settings.showOverlay = false },
                sourceMenu: { [weak self] in self?.onShowSourceMenu?() },
                resizeChanged: { [weak self] in self?.resizeChanged() },
                resizeEnded: { [weak self] in self?.resizeEnded() }
            )
        )
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: layout.metrics.windowSize)
        panel.contentView = host

        applyPlacement()
        observe()
    }

    // MARK: Show / hide

    var isShown: Bool { layout.isVisible }

    func show() {
        autoHidden = false
        guard !layout.isVisible else { return }
        applyPlacement()
        panel.alphaValue = 1
        raise()
        // Let the window appear at full transparency first so the fade-in animates.
        DispatchQueue.main.async {
            withAnimation(Theme.morph) { self.layout.isVisible = true }
            self.updateHover()
        }
    }

    func hide() {
        guard layout.isVisible else { return }
        hoverTask?.cancel()
        panel.ignoresMouseEvents = true
        withAnimation(.easeIn(duration: 0.2)) {
            layout.isVisible = false
            layout.isHovering = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, !self.layout.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: Placement

    private func screen(for id: UInt32?) -> NSScreen {
        NSScreen.screens.first { $0.displayID == id } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func screenUnderMouse() -> NSScreen {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? screen(for: nil)
    }

    private func targetOrigin(for p: Placement) -> (CGPoint, DockEdge?, wing: CGRect?, screen: NSScreen) {
        let m = layout.metrics
        switch p {
        case let .notch(side, id):
            // Notch gone (lid closed, other display): fall back to top center.
            let s = NSScreen.screens.first { $0.displayID == id && $0.notchRect != nil } ?? NSScreen.screens.first { $0.notchRect != nil }
            guard let s, let notch = s.notchRect else {
                return (m.windowOrigin(docked: .top, along: 0.5, in: screen(for: id).dockingFrame), .top, nil, screen(for: id))
            }
            let l = m.notchLayout(notch: notch, side: side, in: s.dockingFrame)
            return (l.windowOrigin, .top, l.wing, s)
        case let .docked(edge, along, id):
            let s = screen(for: id)
            return (m.windowOrigin(docked: edge, along: along, in: s.dockingFrame), edge, nil, s)
        case let .floating(x, y, id):
            let s = screen(for: id)
            return (m.floatingOrigin(ratio: CGPoint(x: x, y: y), in: s.dockingFrame), nil, nil, s)
        }
    }

    private func applyPlacement() {
        spring.stop()
        let (ideal, edge, wing, screen) = targetOrigin(for: placement)
        let fitted = fit(ideal, on: screen)
        panel.setFrameOrigin(fitted.origin)
        applyLevel()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            layout.contentShift = fitted.shift
            layout.edge = edge
            setWing(wing)
            layout.isExpanded = edge == nil || !settings.autoCollapse
        }
    }

    /// A window crossing onto another display misbehaves when displays have separate Spaces
    /// (animations stall, it can end up behind other windows), so keep it inside `screen` and
    /// return the content shift that puts everything where `ideal` would have.
    private func fit(_ ideal: CGPoint, on screen: NSScreen) -> (origin: CGPoint, shift: CGSize) {
        let s = layout.metrics.windowSize, f = screen.frame
        let x = ideal.x.clamped(to: f.minX...max(f.minX, f.maxX - s.width))
        let y = ideal.y.clamped(to: f.minY...max(f.minY, f.maxY - s.height))
        return (CGPoint(x: x, y: y), CGSize(width: ideal.x - x, height: y - ideal.y))
    }

    /// Changes the content shift while moving the window the opposite way, so nothing jumps.
    private func setShift(_ shift: CGSize) {
        let old = layout.contentShift
        guard shift != old else { return }
        var o = panel.frame.origin
        o.x -= shift.width - old.width
        o.y += shift.height - old.height
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { layout.contentShift = shift }
        panel.setFrameOrigin(o)
    }

    private func setWing(_ wing: CGRect?) {
        layout.notchWing = wing
        if case let .notch(side, _) = placement { layout.notchSide = side }
    }

    /// The wing lives in the menu bar row, so it must float above the menu bar.
    private func applyLevel() {
        var inNotch = false
        if case .notch = placement { inNotch = true }
        panel.applyLevel(overFullScreen: settings.overFullScreen || inNotch)
    }

    /// Attach beside the notch on the screen that has one (menu action).
    func attachToNotch(side: NotchSide = .right) {
        guard let s = NSScreen.screens.first(where: { $0.notchRect != nil }) else { return }
        placement = .notch(side: side, screen: s.displayID)
        let (ideal, _, wing, screen) = targetOrigin(for: placement)
        let fitted = fit(ideal, on: screen)
        let origin = fitted.origin
        applyLevel()
        setShift(fitted.shift)
        withAnimation(Theme.morph) {
            layout.edge = .top
            setWing(wing)
            layout.isExpanded = !settings.autoCollapse
        }
        if layout.isVisible {
            spring.animate(to: origin, ceiling: origin.y) { [weak self] in self?.updateHover() }
        } else {
            settings.showOverlay = true
            showIfAllowed()
        }
    }

    static var hasNotchScreen: Bool { NSScreen.screens.contains { $0.notchRect != nil } }

    /// Current card rect in screen coordinates (card is always drawn when dragging).
    private func cardScreenRect() -> CGRect {
        screenRect(layout.metrics.cardRect(docked: layout.edge))
    }

    private func screenRect(_ local: CGRect) -> CGRect {
        let f = panel.frame, s = layout.contentShift
        return CGRect(x: f.minX + local.minX + s.width, y: f.maxY - local.maxY - s.height, width: local.width, height: local.height)
    }

    // MARK: Drag

    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if !layout.isDragging {
            spring.stop()
            hoverTask?.cancel()
            placementBeforeDrag = placement
            dragStartMouse = mouse
            // Drag math assumes unshifted content; move the window to compensate.
            setShift(.zero)
            dragStartOrigin = panel.frame.origin
            dragSamples = []
            withAnimation(Theme.morph) {
                layout.isDragging = true
                layout.edge = nil
                layout.notchWing = nil
                layout.isExpanded = true
            }
        }

        var origin = CGPoint(x: dragStartOrigin.x + mouse.x - dragStartMouse.x, y: dragStartOrigin.y + mouse.y - dragStartMouse.y)
        let vf = screenUnderMouse().dockingFrame
        var preview: DockEdge?
        if magnetActive {
            let m = layout.metrics
            let card = m.floatingCard(windowOrigin: origin)
            let pull = EdgeSnapper.magnetOffset(card: card, in: vf, threshold: settings.snapDistance, gap: m.dockGap)
            origin.x += pull.dx
            origin.y += pull.dy
            preview = EdgeSnapper.nearestEdge(card: m.floatingCard(windowOrigin: origin), in: vf, threshold: settings.snapDistance)
        }
        panel.setFrameOrigin(origin)

        let now = CACurrentMediaTime()
        dragSamples.append((now, mouse))
        dragSamples.removeAll { now - $0.t > 0.08 }

        if preview != layout.snapPreview {
            if preview != nil { haptic(.alignment) }
            withAnimation(Theme.snappy) { layout.snapPreview = preview }
        }
        updateTilt()
    }

    /// Leans the card into fast horizontal drags, then settles when the pointer rests.
    private func updateTilt() {
        guard !Theme.reduceMotion else { return }
        let tilt = Double((releaseVelocity().dx / 400).clamped(to: -5...5))
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.7)) { layout.dragTilt = tilt }
        tiltTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.45)) { self?.layout.dragTilt = 0 }
        }
        tiltTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: task)
    }

    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func dragEnded() {
        guard layout.isDragging else { return }
        let velocity = releaseVelocity()
        let screen = screenUnderMouse()
        let vf = screen.dockingFrame
        let m = layout.metrics
        let card = m.floatingCard(windowOrigin: panel.frame.origin)
        let decision = EdgeSnapper.decide(
            card: card, visibleFrame: vf, screens: NSScreen.screens.map(\.frame),
            threshold: settings.snapDistance, magnet: magnetActive, metrics: m
        )

        tiltTask?.cancel()
        withAnimation(Theme.snappy) {
            layout.isDragging = false
            layout.snapPreview = nil
        }
        // Release wobble: the card swings back upright past zero.
        withAnimation(Theme.reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.4)) { layout.dragTilt = 0 }

        switch decision {
        case .dismiss:
            // Thrown off-screen: glide out, then restore the previous spot for next time.
            let o = panel.frame.origin
            spring.animate(to: CGPoint(x: o.x + velocity.dx * 0.12, y: o.y + velocity.dy * 0.12), velocity: velocity)
            if let before = placementBeforeDrag { placement = before }
            settings.showOverlay = false

        case let .dock(edge, along):
            let target: CGPoint
            var ceiling: CGFloat?
            if edge == .top, settings.attachToNotch, let notch = screen.notchRect,
               abs(card.midX - notch.midX) < m.cardSize.width / 2 + 40 {
                // Dropped at the top near the notch: attach beside it, on the side it was dropped.
                let side: NotchSide = card.midX < notch.midX - 20 ? .left : .right
                placement = .notch(side: side, screen: screen.displayID)
                let l = m.notchLayout(notch: notch, side: side, in: vf)
                target = l.windowOrigin
                ceiling = l.windowOrigin.y
                withAnimation(Theme.morph) {
                    layout.edge = .top
                    setWing(l.wing)
                }
            } else {
                placement = .docked(edge: edge, along: along, screen: screen.displayID)
                target = m.windowOrigin(docked: edge, along: along, in: vf)
                withAnimation(Theme.morph) { layout.edge = edge }
            }
            applyLevel()
            let fitted = fit(target, on: screen)
            setShift(fitted.shift)
            // Never overshoot past the screen top onto a display above.
            if fitted.origin.y < target.y || ceiling != nil { ceiling = fitted.origin.y }
            spring.animate(to: fitted.origin, velocity: velocity, ceiling: ceiling) { [weak self] in
                self?.haptic(.levelChange)
                self?.updateHover()
                self?.scheduleHoverChange()
            }

        case .float:
            let target = m.clampedFloatingOrigin(panel.frame.origin, in: vf)
            let ratio = m.floatingRatio(windowOrigin: target, in: vf)
            placement = .floating(x: ratio.x, y: ratio.y, screen: screen.displayID)
            applyLevel()
            let fitted = fit(target, on: screen)
            setShift(fitted.shift)
            spring.animate(to: fitted.origin, velocity: velocity) { [weak self] in self?.updateHover() }
        }
    }

    /// Holding ⌥ while dragging places the player freely, even right next to an edge.
    private var magnetActive: Bool {
        settings.magnetEnabled && !NSEvent.modifierFlags.contains(.option)
    }

    // MARK: Resize

    private func resizeChanged() {
        let mouse = NSEvent.mouseLocation
        let corner = layout.resizeCorner
        if !layout.isResizing {
            spring.stop()
            hoverTask?.cancel()
            layout.isResizing = true
            resizeStartMouse = mouse
            resizeStartWidth = layout.metrics.cardSize.width
            resizeAnchor = currentAnchor()
        }
        // Grow when dragging away from the anchored corner, along whichever axis moved more.
        let dx = (mouse.x - resizeStartMouse.x) * (corner.right ? 1 : -1)
        let dy = (mouse.y - resizeStartMouse.y) * (corner.bottom ? -1 : 1)
        let aspect = OverlayMetrics.baseCardSize.width / OverlayMetrics.baseCardSize.height
        let grow = abs(dx) >= abs(dy * aspect) ? dx : dy * aspect
        applyScale(OverlayMetrics.scale(forCardWidth: resizeStartWidth + grow), anchor: resizeAnchor)
    }

    private func resizeEnded() {
        guard layout.isResizing else { return }
        layout.isResizing = false
        settings.cardScale = Double(layout.metrics.scale)
        updateHover()
    }

    /// Screen point of the card corner opposite the resize grip.
    private func currentAnchor() -> CGPoint {
        let card = screenRect(layout.cardRect), corner = layout.resizeCorner
        return CGPoint(x: corner.right ? card.minX : card.maxX, y: corner.bottom ? card.maxY : card.minY)
    }

    /// Resizes the player, keeping `anchor` (a card corner, screen coordinates) in place.
    private func applyScale(_ scale: CGFloat, anchor: CGPoint) {
        guard abs(scale - layout.metrics.scale) > 0.0005 else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { layout.metrics.scale = scale }

        let m = layout.metrics, size = m.cardSize, corner = layout.resizeCorner
        let card = CGRect(
            x: corner.right ? anchor.x : anchor.x - size.width,
            y: corner.bottom ? anchor.y - size.height : anchor.y,
            width: size.width, height: size.height
        )
        switch placement {
        case let .docked(edge, _, id):
            placement = .docked(edge: edge, along: m.along(card: card, edge: edge, in: screen(for: id).dockingFrame), screen: id)
        case let .floating(_, _, id):
            let r = m.floatingRatio(windowOrigin: CGPoint(x: card.minX - m.padding, y: card.minY - m.padding), in: screen(for: id).dockingFrame)
            placement = .floating(x: r.x, y: r.y, screen: id)
        case .notch:
            break // Stays centered under the notch.
        }
        reposition()
    }

    /// Puts the window at the current placement and size without touching expanded state.
    private func reposition() {
        let (ideal, _, wing, screen) = targetOrigin(for: placement)
        let fitted = fit(ideal, on: screen)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            layout.contentShift = fitted.shift
            setWing(wing)
        }
        panel.setFrame(CGRect(origin: fitted.origin, size: layout.metrics.windowSize), display: true)
    }

    private func releaseVelocity() -> CGVector {
        guard let first = dragSamples.first, let last = dragSamples.last, last.t - first.t > 0.005 else { return .zero }
        let dt = last.t - first.t
        return CGVector(dx: (last.p.x - first.p.x) / dt, dy: (last.p.y - first.p.y) / dt)
    }

    // MARK: Hover

    private func updateHover() {
        guard layout.isVisible, !layout.isDragging, !layout.isResizing else { return }
        let mouse = NSEvent.mouseLocation
        let inside = layout.interactiveRects.contains { screenRect($0).insetBy(dx: -1, dy: -1).contains(mouse) }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != layout.isHovering {
            withAnimation(.easeOut(duration: 0.15)) { layout.isHovering = inside }
            scheduleHoverChange()
        }
    }

    private func scheduleHoverChange() {
        hoverTask?.cancel()
        guard layout.edge != nil, settings.autoCollapse, !layout.isDragging else { return }
        let wantExpanded = layout.isHovering
        guard wantExpanded != layout.isExpanded else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.layout.isHovering == wantExpanded else { return }
            self.setExpanded(wantExpanded)
        }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (wantExpanded ? settings.hoverDelay : 0.7), execute: task)
    }

    private func setExpanded(_ expanded: Bool) {
        guard layout.isExpanded != expanded else { return }
        peekTask?.cancel()
        // Opening: make sure we're in front of anything that got ordered above us meanwhile.
        if expanded { raise() }
        withAnimation(Theme.morph) {
            layout.isExpanded = expanded
            layout.isPeeking = false
        }
        // The interactive region changed size; re-evaluate the pointer against it.
        DispatchQueue.main.async { self.updateHover() }
    }

    private func raise() {
        applyLevel()
        panel.orderFrontRegardless()
    }

    // MARK: Observation

    private func observe() {
        // Mouse events over the menu bar don't always reach event monitors, so also poll the
        // pointer. Without this, the card could open without taking clicks (they'd fall through
        // to the window behind it).
        let poll = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.layout.isVisible, !self.layout.isDragging else { return }
                self.updateHover()
            }
        }
        RunLoop.main.add(poll, forMode: .common)
        hoverPoll = poll

        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in
            self?.updateHover()
            return e
        }) { monitors.append(l) }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.applyPlacement() }
            .store(in: &bag)

        settings.$cardScale.dropFirst().removeDuplicates()
            .sink { [weak self] v in
                DispatchQueue.main.async {
                    guard let self, !self.layout.isResizing else { return }
                    self.applyScale(CGFloat(v).clamped(to: OverlayMetrics.scaleRange), anchor: self.currentAnchor())
                }
            }
            .store(in: &bag)

        settings.$overFullScreen.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyLevel() } }
            .store(in: &bag)

        settings.$autoCollapse.dropFirst()
            .sink { [weak self] v in
                guard let self, self.layout.edge != nil else { return }
                self.setExpanded(!v || self.layout.isHovering)
            }
            .store(in: &bag)

        settings.$showOverlay.dropFirst().removeDuplicates()
            .sink { [weak self] v in
                DispatchQueue.main.async { v ? self?.showIfAllowed() : self?.hide() }
            }
            .store(in: &bag)

        router.$resolution
            .map { $0.nowPlaying?.trackKey }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] key in if key != nil { self?.peek() } }
            .store(in: &bag)

        Publishers.CombineLatest(router.$resolution.map { $0.nowPlaying == nil }.removeDuplicates(), settings.$hideWhenIdle)
            .sink { [weak self] idle, hideWhenIdle in self?.idleChanged(idle: idle, hideWhenIdle: hideWhenIdle) }
            .store(in: &bag)
    }

    /// Pop the collapsed tab out for a moment so a track change is noticeable at a glance.
    private func peek() {
        guard layout.isVisible, layout.edge != nil, !layout.isExpanded, !layout.isDragging, !Theme.reduceMotion else { return }
        peekTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.52)) { layout.isPeeking = true }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(Theme.morph) { self?.layout.isPeeking = false }
        }
        peekTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
    }

    func showIfAllowed() {
        guard settings.showOverlay else { return }
        if settings.hideWhenIdle && router.resolution.nowPlaying == nil {
            autoHidden = true
            return
        }
        show()
    }

    private func idleChanged(idle: Bool, hideWhenIdle: Bool) {
        idleTask?.cancel()
        guard settings.showOverlay else { return }
        if idle && hideWhenIdle {
            // Wait a moment: players briefly report nothing between tracks.
            let task = DispatchWorkItem { [weak self] in
                guard let self, self.router.resolution.nowPlaying == nil else { return }
                self.autoHidden = true
                self.hide()
            }
            idleTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: task)
        } else if autoHidden || (!idle && !layout.isVisible && settings.showOverlay) {
            show()
        }
    }
}

struct OverlayActions {
    var dragChanged: () -> Void
    var dragEnded: () -> Void
    var expand: () -> Void
    var close: () -> Void
    var sourceMenu: () -> Void
    var resizeChanged: () -> Void = {}
    var resizeEnded: () -> Void = {}
}

extension NSScreen {
    var displayID: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }

    /// The notch, in screen coordinates, spanning the menu bar row; nil on displays without one.
    var notchRect: CGRect? {
        guard let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea, r.minX > l.maxX else { return nil }
        return CGRect(x: l.maxX, y: l.minY, width: r.minX - l.maxX, height: frame.maxY - l.minY)
    }

    /// Area the overlay may occupy: the visible frame, but never under the notch or the menu bar,
    /// even when the menu bar auto-hides (then `visibleFrame` would include its space).
    var dockingFrame: CGRect {
        var f = visibleFrame
        let reservedTop = max(safeAreaInsets.top, NSStatusBar.system.thickness)
        let top = min(f.maxY, frame.maxY - reservedTop)
        f.size.height = top - f.minY
        return f
    }
}
