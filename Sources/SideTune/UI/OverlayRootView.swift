import SwiftUI

/// Whole overlay: one shape that morphs between the edge tab and the player card.
struct OverlayRootView: View {
    @ObservedObject var layout: OverlayLayout
    @ObservedObject var router: MediaRouter
    @ObservedObject var settings: Settings
    let actions: OverlayActions

    @Namespace private var namespace

    var body: some View {
        let m = layout.metrics
        let card = layout.showsCard
        let wing = card ? nil : layout.wingRect
        let rect = card ? layout.cardRect : (wing ?? layout.tabRect)
        let attached = layout.notchWing != nil
        // The tab is square on the side touching the screen edge so it reads as attached;
        // the notch wing is square everywhere except its outer bottom corner, to continue the notch.
        let top: CGFloat = attached ? 4 : 26
        let radii: RectangleCornerRadii = card ? .init(topLeading: top, bottomLeading: 26, bottomTrailing: 26, topTrailing: top)
            : wing != nil ? wingRadii(layout.notchSide) : tabRadii(layout.edge ?? .right)
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        let accent = Color(nsColor: router.accent)

        ZStack(alignment: .topLeading) {
            // Beside the notch, the black wing stays put while the card opens below it.
            if let base = layout.notchWing, layout.isVisible {
                UnevenRoundedRectangle(cornerRadii: wingRadii(layout.notchSide), style: .continuous)
                    .fill(.black)
                    .frame(width: base.width, height: base.height)
                    .offset(x: base.minX, y: base.minY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            ZStack {
                CardBackground(
                    artwork: settings.tintWithArtwork ? router.resolution.nowPlaying?.artwork : nil,
                    artworkKey: router.resolution.nowPlaying?.artworkKey ?? "",
                    accent: accent,
                    isPlaying: router.resolution.nowPlaying?.isPlaying ?? false,
                    solid: wing != nil
                )

                if card {
                    PlayerCard(router: router, layout: layout, settings: settings, actions: actions, namespace: namespace)
                        .frame(width: m.cardSize.width, height: m.cardSize.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else if wing != nil {
                    NotchWing(
                        nowPlaying: router.resolution.nowPlaying, side: layout.notchSide, accent: accent,
                        overlap: m.wingOverlap, isPeeking: layout.isPeeking, namespace: namespace
                    )
                    .transition(.opacity)
                } else {
                    EdgeTab(
                        nowPlaying: router.resolution.nowPlaying, edge: layout.edge ?? .right,
                        accent: accent, isPeeking: layout.isPeeking, namespace: namespace
                    )
                    .transition(.opacity)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .clipShape(shape)
            // Top-lit edge: brighter along the top, fading down the sides.
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(layout.isHovering ? 0.28 : 0.2), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1
            ).opacity(wing != nil ? 0 : 1))
            .overlay(SnapGlow(edge: layout.snapPreview, color: accent))
            .overlay(alignment: gripAlignment) {
                if card && wing == nil && !layout.isDragging {
                    ResizeGrip(corner: layout.resizeCorner, onChanged: actions.resizeChanged, onEnded: actions.resizeEnded)
                        .opacity(layout.isHovering || layout.isResizing ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: layout.isHovering)
                }
            }
            .shadow(color: .black.opacity(wing != nil ? 0 : layout.isDragging ? 0.45 : 0.32), radius: layout.isDragging ? 22 : card ? 16 : 9, y: layout.isDragging ? 12 : 6)
            .scaleEffect(layout.isDragging ? 1.025 : 1)
            .rotationEffect(.degrees(layout.dragTilt))
            .rotation3DEffect(.degrees(lean), axis: leanAxis, anchor: .center, perspective: 0.5)
            .contentShape(shape)
            .onTapGesture { if !card { actions.expand() } }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { _ in actions.dragChanged() }
                    .onEnded { _ in actions.dragEnded() }
            )
            .offset(x: rect.minX, y: rect.minY)
        }
        .offset(layout.contentShift)
        .frame(width: m.windowSize.width, height: m.windowSize.height, alignment: .topLeading)
        .opacity(layout.isVisible ? 1 : 0)
        .scaleEffect(layout.isVisible ? 1 : 0.9, anchor: anchor)
        .offset(hiddenOffset)
        .environment(\.colorScheme, .dark)
    }

    private var gripAlignment: Alignment {
        let c = layout.resizeCorner
        switch (c.right, c.bottom) {
        case (true, true): return .bottomTrailing
        case (false, true): return .bottomLeading
        case (true, false): return .topTrailing
        case (false, false): return .topLeading
        }
    }

    private func wingRadii(_ side: NotchSide) -> RectangleCornerRadii {
        let r: CGFloat = 10
        return side == .right
            ? .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: 0)
            : .init(topLeading: 0, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
    }

    private func tabRadii(_ edge: DockEdge) -> RectangleCornerRadii {
        let r: CGFloat = 17, flush: CGFloat = 3
        switch edge {
        case .left: return .init(topLeading: flush, bottomLeading: flush, bottomTrailing: r, topTrailing: r)
        case .right: return .init(topLeading: r, bottomLeading: r, bottomTrailing: flush, topTrailing: flush)
        case .top: return .init(topLeading: flush, bottomLeading: r, bottomTrailing: r, topTrailing: flush)
        case .bottom: return .init(topLeading: r, bottomLeading: flush, bottomTrailing: flush, topTrailing: r)
        }
    }

    /// While a dock is previewed, the card tips its near side toward the screen edge, as if pulled.
    private var lean: Double {
        switch layout.snapPreview {
        case .left?, .bottom?: return -7
        case .right?, .top?: return 7
        case nil: return 0
        }
    }

    private var leanAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        layout.snapPreview?.isSide == false ? (1, 0, 0) : (0, 1, 0)
    }

    /// Grow out of / shrink into the docked edge.
    private var anchor: UnitPoint {
        switch layout.edge {
        case .left?: return .leading
        case .right?: return .trailing
        case .top?: return .top
        case .bottom?: return .bottom
        case nil: return .center
        }
    }

    private var hiddenOffset: CGSize {
        guard !layout.isVisible else { return .zero }
        switch layout.edge {
        case .left?: return CGSize(width: -24, height: 0)
        case .right?: return CGSize(width: 24, height: 0)
        case .top?: return CGSize(width: 0, height: -24)
        case .bottom?: return CGSize(width: 0, height: 24)
        case nil: return CGSize(width: 0, height: 10)
        }
    }
}

struct CardBackground: View {
    let artwork: NSImage?
    let artworkKey: String
    let accent: Color
    var isPlaying = false
    /// Pure black, to merge with the notch.
    var solid = false

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow)
            Color.black.opacity(0.42)
            if let artwork {
                // Slowly drifting, rotating blur of the artwork while music plays; frozen when paused.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying || Theme.reduceMotion)) { context in
                    let t = Theme.clock(context.date)
                    // Color.clear sizes to the container; the image fills it without affecting layout.
                    Color.clear
                        .overlay {
                            Image(nsImage: artwork)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(1.7)
                                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 90) * 4))
                                .offset(x: sin(t * 0.23) * 18, y: cos(t * 0.17) * 10)
                                .blur(radius: 42)
                                .saturation(1.7)
                        }
                        .clipped()
                }
                .opacity(0.72)
                .id(artworkKey)
                .transition(.opacity)
            }
            // Accent wash from the top-left, vignette to the bottom-right for text contrast.
            LinearGradient(colors: [accent.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .center)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
            Color.black.opacity(solid ? 1 : 0)
        }
        .animation(Theme.timed(.easeInOut(duration: 0.3)), value: solid)
        .animation(Theme.timed(.easeInOut(duration: 0.6)), value: artworkKey)
        .allowsHitTesting(false)
    }
}

/// Glowing bar on the side that will dock, shown while dragging near an edge.
struct SnapGlow: View {
    let edge: DockEdge?
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if let edge {
                let side = edge.isSide
                Capsule()
                    .fill(color)
                    .frame(width: side ? 4 : 70, height: side ? 70 : 4)
                    .shadow(color: color.opacity(0.9), radius: 8)
                    .shadow(color: color.opacity(0.6), radius: 16)
                    .position(position(edge, geo.size))
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            }
        }
        .allowsHitTesting(false)
    }

    private func position(_ edge: DockEdge, _ s: CGSize) -> CGPoint {
        let inset: CGFloat = -7
        switch edge {
        case .left: return CGPoint(x: inset, y: s.height / 2)
        case .right: return CGPoint(x: s.width - inset, y: s.height / 2)
        case .top: return CGPoint(x: s.width / 2, y: inset)
        case .bottom: return CGPoint(x: s.width / 2, y: s.height - inset)
        }
    }
}

/// Collapsed pill: artwork thumbnail and a live equalizer.
struct EdgeTab: View {
    let nowPlaying: NowPlaying?
    let edge: DockEdge
    let accent: Color
    var isPeeking = false
    let namespace: Namespace.ID

    var body: some View {
        let layout = edge.isSide ? AnyLayout(VStackLayout(spacing: 11)) : AnyLayout(HStackLayout(spacing: 11))
        layout {
            ArtworkView(nowPlaying: nowPlaying, size: 28, radius: 8, accent: accent)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .shadow(color: accent.opacity(isPeeking ? 0.9 : 0), radius: isPeeking ? 9 : 0)
                .scaleEffect(isPeeking ? 1.18 : 1)
                .animation(.spring(response: 0.36, dampingFraction: 0.5), value: isPeeking)
            AudioBars(isPlaying: nowPlaying?.isPlaying ?? false, color: accent, barCount: 4, height: 14, barWidth: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Collapsed player beside the notch: black like the notch, artwork and equalizer.
struct NotchWing: View {
    let nowPlaying: NowPlaying?
    let side: NotchSide
    let accent: Color
    let overlap: CGFloat
    var isPeeking = false
    let namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 9) {
            ArtworkView(nowPlaying: nowPlaying, size: 20, radius: 5, accent: accent)
                .matchedGeometryEffect(id: "artwork", in: namespace)
                .shadow(color: accent.opacity(isPeeking ? 0.9 : 0), radius: isPeeking ? 6 : 0)
                .scaleEffect(isPeeking ? 1.15 : 1)
                .animation(.spring(response: 0.36, dampingFraction: 0.5), value: isPeeking)
            AudioBars(isPlaying: nowPlaying?.isPlaying ?? false, color: accent, barCount: 4, height: 11, barWidth: 2.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep content out of the part tucked under the notch.
        .padding(side == .right ? .leading : .trailing, overlap)
    }
}

/// Corner grip for resizing: three short diagonal strokes, shown on hover.
struct ResizeGrip: View {
    let corner: (right: Bool, bottom: Bool)
    let onChanged: () -> Void
    let onEnded: () -> Void
    @State private var hovering = false

    var body: some View {
        Canvas { ctx, size in
            // Strokes drawn for the bottom-right corner, then mirrored into place.
            let edge = CGPoint(x: size.width - 4, y: size.height - 4)
            for i in 1...3 {
                let k = CGFloat(i) * 3.2
                var p = Path()
                p.move(to: CGPoint(x: edge.x, y: edge.y - k))
                p.addLine(to: CGPoint(x: edge.x - k, y: edge.y))
                ctx.stroke(p, with: .color(.white.opacity(hovering ? 0.75 : 0.4)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: 16, height: 16)
        .scaleEffect(x: corner.right ? 1 : -1, y: corner.bottom ? 1 : -1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in onChanged() }
                .onEnded { _ in onEnded() }
        )
        .help("Drag to resize")
    }
}
