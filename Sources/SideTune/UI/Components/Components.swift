import SwiftUI

// MARK: Artwork

struct ArtworkView: View {
    let nowPlaying: NowPlaying?
    let size: CGFloat
    let radius: CGFloat
    var accent: Color = .white
    /// +1 slides new artwork in from the right (next track), -1 from the left.
    var direction: CGFloat = 1
    /// Soft accent halo while playing.
    var glows = false

    var body: some View {
        let playing = nowPlaying?.isPlaying == true
        let slide = size * 0.35 * direction
        ZStack {
            if let image = nowPlaying?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .id(nowPlaying?.artworkKey)
                    .transition(.asymmetric(
                        insertion: .offset(x: slide).combined(with: .scale(scale: 1.15)).combined(with: .opacity),
                        removal: .offset(x: -slide).combined(with: .scale(scale: 0.9)).combined(with: .opacity)
                    ))
            } else {
                placeholder.transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(accent)
                .blur(radius: size * 0.14)
                .opacity(glows && playing ? 0.45 : 0)
                .scaleEffect(glows && playing ? 1 : 0.8)
        )
        // Shrinks a touch when paused, like the Music app.
        .scaleEffect(nowPlaying?.isPlaying == false ? 0.93 : 1)
        .animation(Theme.morph, value: nowPlaying?.isPlaying)
        .animation(.easeInOut(duration: 0.35), value: nowPlaying?.artworkKey)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: Audio bars

/// Little equalizer that dances while playing and settles flat when paused.
struct AudioBars: View {
    let isPlaying: Bool
    let color: Color
    var barCount = 4
    var height: CGFloat = 14
    var barWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.75) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(i, t))
                }
            }
            .frame(height: height)
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
    }

    private func barHeight(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let minH = barWidth
        guard isPlaying else { return minH }
        let d = Double(i)
        // Two sines at unrelated rates per bar reads as organic rather than looping.
        let v = 0.5 + 0.3 * sin(t * (5.1 + d * 1.7) + d * 1.3) + 0.2 * sin(t * (8.3 - d * 0.9) + d * 2.1)
        return minH + (height - minH) * CGFloat(v.clamped(to: 0...1))
    }
}

// MARK: Marquee

/// Single line that scrolls when it doesn't fit, pausing at the start of each loop.
struct MarqueeText: View {
    let text: String
    let font: Font
    var gap: CGFloat = 36
    var speed: CGFloat = 28

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text).font(font).lineLimit(1).opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let overflow = textWidth > geo.size.width + 1
                    HStack(spacing: gap) {
                        label
                        if overflow { label }
                    }
                    .offset(x: overflow ? offset : 0)
                    .frame(width: geo.size.width, alignment: .leading)
                    .mask(fadeMask(leading: overflow && offset < 0, trailing: overflow))
                    .task(id: "\(text)|\(overflow)") { await loop(overflow: overflow) }
                }
            }
            .background(
                Text(text).font(font).fixedSize().hidden()
                    .background(GeometryReader { g in Color.clear.preference(key: WidthKey.self, value: g.size.width) })
            )
            .onPreferenceChange(WidthKey.self) { textWidth = $0 }
            .clipped()
    }

    private var label: some View { Text(text).font(font).lineLimit(1).fixedSize() }

    /// Fades the trailing edge when text overflows, and the leading edge only while scrolling.
    private func fadeMask(leading: Bool, trailing: Bool) -> some View {
        LinearGradient(
            stops: [
                .init(color: leading ? .clear : .black, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.88),
                .init(color: trailing ? .clear : .black, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    @MainActor
    private func loop(overflow: Bool) async {
        offset = 0
        guard overflow, !Theme.reduceMotion else { return }
        let distance = textWidth + gap
        let duration = Double(distance / speed)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.2))
            if Task.isCancelled { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { offset = 0 }
        }
    }

    private struct WidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

// MARK: Scrub bar

struct ScrubBar: View {
    let nowPlaying: NowPlaying?
    let accent: Color
    let enabled: Bool
    /// Times under the bar (full-width bar) instead of on either side.
    var stacked = false
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let duration = nowPlaying?.duration ?? 0
            let elapsed = nowPlaying?.elapsed(at: context.date) ?? 0
            let live = duration > 0 ? elapsed / duration : 0
            let fraction = (dragFraction ?? live).clamped(to: 0...1)
            let shown = dragFraction.map { $0 * duration } ?? elapsed

            let remaining = duration > 0 ? "-" + formatTime(max(duration - shown, 0)) : "--:--"
            Group {
                if stacked {
                    VStack(spacing: 2) {
                        bar(fraction: fraction, duration: duration)
                        HStack {
                            Text(formatTime(shown))
                            Spacer()
                            Text(remaining)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(formatTime(shown))
                            .frame(width: 34, alignment: .trailing)
                        bar(fraction: fraction, duration: duration)
                        Text(remaining)
                            .frame(width: 38, alignment: .leading)
                    }
                }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(dragFraction != nil ? 0.85 : 0.55))
        }
        .opacity(enabled && (nowPlaying?.duration ?? 0) > 0 ? 1 : 0.45)
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        let active = hovering || dragFraction != nil
        return GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = active ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                    .frame(width: w, height: h)
                Capsule()
                    .fill(LinearGradient(colors: [accent.opacity(0.85), accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: duration > 0 ? max(w * fraction, h) : 0, height: h)
                    .animation(dragFraction == nil ? .linear(duration: 0.25) : nil, value: fraction)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .frame(width: 11, height: 11)
                    .offset(x: w * fraction - 5.5)
                    .scaleEffect(active ? 1 : 0.2)
                    .opacity(active ? 1 : 0)
                    .animation(dragFraction == nil ? .linear(duration: 0.25) : nil, value: fraction)
            }
            .frame(width: w, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled, duration > 0 else { return }
                        dragFraction = Double((v.location.x / w).clamped(to: 0...1))
                    }
                    .onEnded { v in
                        guard enabled, duration > 0 else { return }
                        let f = Double((v.location.x / w).clamped(to: 0...1))
                        onSeek(f * duration)
                        // Hold the dragged position until the player reports the new time.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dragFraction = nil }
                    }
            )
        }
        .frame(height: 14)
        .onHover { h in withAnimation(Theme.snappy) { hovering = h } }
        .animation(Theme.snappy, value: active)
    }
}

// MARK: Transport

struct PlaybackModes {
    var shuffle: Bool
    var repeatMode: RepeatMode
    var nextRepeat: RepeatMode
}

struct TransportControls: View {
    let isPlaying: Bool
    let enabled: Bool
    var scale: CGFloat = 1
    var accent: Color = .white
    /// Shuffle and repeat buttons flank the transport when the app supports them.
    var modes: PlaybackModes? = nil
    let send: (MediaCommand) -> Void

    @State private var prevBounce = 0
    @State private var nextBounce = 0
    @State private var ripple = 0

    var body: some View {
        HStack(spacing: 0) {
            if let modes {
                ModeButton(systemImage: "shuffle", active: modes.shuffle, accent: accent, scale: scale, help: modes.shuffle ? "Shuffle on" : "Shuffle off") {
                    send(.setShuffle(!modes.shuffle))
                }
                Spacer(minLength: 4)
            }

            HStack(spacing: 20 * scale) {
                IconButton(size: 15 * scale, hit: 30 * scale) {
                    prevBounce += 1
                    send(.previous)
                } label: {
                    Image(systemName: "backward.fill").symbolEffect(.bounce.down, value: prevBounce)
                }

                PlayButton(isPlaying: isPlaying, accent: accent, size: 38 * scale) {
                    ripple += 1
                    send(.togglePlayPause)
                }
                .background(RippleRing(trigger: ripple, color: accent).frame(width: 38 * scale, height: 38 * scale))

                IconButton(size: 15 * scale, hit: 30 * scale) {
                    nextBounce += 1
                    send(.next)
                } label: {
                    Image(systemName: "forward.fill").symbolEffect(.bounce.down, value: nextBounce)
                }
            }

            if let modes {
                Spacer(minLength: 4)
                ModeButton(
                    systemImage: modes.repeatMode == .one ? "repeat.1" : "repeat",
                    active: modes.repeatMode != .off, accent: accent, scale: scale,
                    help: modes.repeatMode == .off ? "Repeat off" : modes.repeatMode == .one ? "Repeat one" : "Repeat all"
                ) {
                    send(.setRepeat(modes.nextRepeat))
                }
            }
        }
        .frame(maxWidth: modes == nil ? nil : .infinity)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Filled disc with the play/pause glyph cut from the accent color.
struct PlayButton: View {
    let isPlaying: Bool
    let accent: Color
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white.opacity(hovering ? 1 : 0.94))
                    .shadow(color: accent.opacity(isPlaying ? 0.55 : 0.25), radius: isPlaying ? 10 : 5)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .offset(x: isPlaying ? 0 : size * 0.035) // optical centering of the triangle
                    .contentTransition(.symbolEffect(.replace.downUp))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PressableCapsuleStyle())
        .scaleEffect(hovering ? 1.06 : 1)
        .onHover { h in withAnimation(Theme.snappy) { hovering = h } }
        .animation(Theme.morph, value: isPlaying)
    }
}

/// Shuffle/repeat toggle: accent-colored with a dot when on.
struct ModeButton: View {
    let systemImage: String
    let active: Bool
    let accent: Color
    var scale: CGFloat = 1
    let help: String
    let action: () -> Void

    var body: some View {
        IconButton(size: 12.5 * scale, hit: 28 * scale, action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(active ? accent : .white.opacity(0.5))
                .contentTransition(.symbolEffect(.replace))
                .overlay(alignment: .bottom) {
                    Circle()
                        .fill(accent)
                        .frame(width: 3.5, height: 3.5)
                        .offset(y: 8 * scale)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.2)
                }
        }
        .animation(Theme.snappy, value: active)
        .help(help)
    }
}

struct IconButton<Label: View>: View {
    let size: CGFloat
    let hit: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: size, weight: .semibold))
                .frame(width: hit, height: hit)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Springy press feedback plus a soft hover disc.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(configuration.isPressed ? 0.7 : 0.95))
                .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.18 : hovering ? 0.1 : 0)))
                .scaleEffect(configuration.isPressed ? 0.84 : 1)
                .animation(Theme.snappy, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: Ripple

/// A ring that bursts outward each time `trigger` changes.
struct RippleRing: View {
    let trigger: Int
    let color: Color

    private struct Value {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1.5)
            .keyframeAnimator(initialValue: Value(), trigger: trigger) { content, v in
                content.scaleEffect(v.scale).opacity(v.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.7, duration: 0.01)
                    SpringKeyframe(1.9, duration: 0.55, spring: .smooth)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0.8, duration: 0.05)
                    LinearKeyframe(0, duration: 0.5)
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: Stagger

/// Rows rise and fade in one after another when a view appears.
struct StaggerIn: ViewModifier {
    let shown: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Theme.reduceMotion ? 0 : 8)
            .blur(radius: shown || Theme.reduceMotion ? 0 : 3)
            .animation(
                Theme.reduceMotion ? .easeOut(duration: 0.15)
                    : .spring(response: 0.42, dampingFraction: 0.82).delay(0.05 + Double(index) * 0.045),
                value: shown
            )
    }
}

extension View {
    func staggerIn(_ shown: Bool, _ index: Int) -> some View { modifier(StaggerIn(shown: shown, index: index)) }
}

// MARK: Track text

/// Title and subtitle that push out sideways on track change, in the skip direction.
struct TrackText: View {
    let text: PlayerText
    let accent: Color
    let direction: CGFloat
    var titleSize: CGFloat = 15
    var subtitleSize: CGFloat = 12.5

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 1) {
                MarqueeText(text: text.title, font: .system(size: titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                Text(text.subtitle)
                    .font(.system(size: subtitleSize, weight: text.subtitleIsStatus ? .medium : .regular))
                    .foregroundStyle(text.subtitleIsStatus ? accent.opacity(0.95) : .white.opacity(0.62))
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .id(text.title)
            .transition(
                Theme.reduceMotion ? .opacity
                    : .push(from: direction > 0 ? .trailing : .leading).combined(with: .opacity)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(Theme.morph, value: text.title)
        .animation(.easeInOut(duration: 0.25), value: text.subtitle)
    }
}
