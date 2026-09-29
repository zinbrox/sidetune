import SwiftUI

/// Title, subtitle and whether transport controls work, for any resolution.
struct PlayerText {
    let title: String
    let subtitle: String
    let subtitleIsStatus: Bool

    @MainActor
    init(_ r: Resolution) {
        let np = r.nowPlaying
        switch r.status {
        case .ok:
            title = np?.title ?? "Nothing playing"
            let parts = [np?.artist, np?.album].compactMap { $0 }.filter { !$0.isEmpty }
            subtitle = parts.isEmpty ? AppInfo.name(np?.bundleID ?? "") : parts.joined(separator: " — ")
            subtitleIsStatus = false
        case .idle:
            title = "Nothing playing"
            subtitle = "Play something in any app"
            subtitleIsStatus = true
        case .notRunning(let id):
            title = np?.title ?? "\(AppInfo.name(id)) isn't open"
            subtitle = np == nil ? "Open it to start listening" : "\(AppInfo.name(id)) isn't open"
            subtitleIsStatus = true
        case .noPermission(let id):
            title = np?.title ?? AppInfo.name(id)
            subtitle = "Allow SideTune to control \(AppInfo.name(id))"
            subtitleIsStatus = true
        case .pinnedIdle(let id):
            title = np?.title ?? "\(AppInfo.name(id)) is ready"
            subtitle = np == nil ? "Press play to start" : "Stopped"
            subtitleIsStatus = true
        case .notCurrent(let id):
            title = np?.title ?? AppInfo.name(id)
            subtitle = "Controls return when \(AppInfo.name(id)) plays"
            subtitleIsStatus = true
        }
    }
}

/// Main expanded card.
struct PlayerCard: View {
    @ObservedObject var router: MediaRouter
    @ObservedObject var layout: OverlayLayout
    @ObservedObject var settings: Settings
    let actions: OverlayActions
    let namespace: Namespace.ID

    @State private var appeared = false

    var body: some View {
        let r = router.resolution
        let np = r.nowPlaying
        let accent = Color(nsColor: router.accent)
        let text = PlayerText(r)
        let s = layout.metrics.scale

        HStack(alignment: .center, spacing: 16 * s) {
            ArtworkButton(nowPlaying: np, size: 136 * s, radius: 18 * s, accent: accent, direction: router.trackDirection)
                .matchedGeometryEffect(id: "artwork", in: namespace)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    SourceBadge(router: router, pinnedID: settings.pinnedBundleID, onTap: actions.sourceMenu)
                    Spacer(minLength: 4)
                    Group {
                        if layout.edge != nil {
                            // Docked: choose between collapsing into the tab and staying full size.
                            HeaderButton(
                                systemImage: settings.autoCollapse ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                                help: settings.autoCollapse ? "Keep open while docked" : "Collapse into a tab when docked",
                                active: !settings.autoCollapse
                            ) { settings.autoCollapse.toggle() }
                        }
                        CloseButton(action: actions.close)
                    }
                    .opacity(layout.isHovering ? 1 : 0)
                    .scaleEffect(layout.isHovering ? 1 : 0.6)
                    .animation(Theme.snappy, value: layout.isHovering)
                }
                .frame(height: 22)
                .staggerIn(appeared, 0)

                Spacer(minLength: 6 * s)

                TrackText(text: text, accent: accent, direction: router.trackDirection, titleSize: 17 * s, subtitleSize: 12.5 * s)
                    .staggerIn(appeared, 1)

                Spacer(minLength: 8 * s)

                ScrubBar(nowPlaying: np, accent: accent, enabled: r.target != .none, stacked: true) { router.send(.seek($0)) }
                    .staggerIn(appeared, 2)

                Spacer(minLength: 4)

                footer(r, accent: accent, scale: s)
                    .frame(maxWidth: .infinity)
                    .staggerIn(appeared, 3)
            }
        }
        .padding(16 * s)
        .onAppear { DispatchQueue.main.async { appeared = true } }
    }

    @ViewBuilder
    private func footer(_ r: Resolution, accent: Color, scale: CGFloat) -> some View {
        switch r.status {
        case .notRunning(let id):
            PillButton(title: "Open \(AppInfo.name(id))", systemImage: "arrow.up.forward.app") { AppInfo.launch(id) }
        case .noPermission:
            PillButton(title: "Open Privacy Settings", systemImage: "lock.open") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
            }
        default:
            TransportControls(
                isPlaying: r.nowPlaying?.isPlaying ?? false, enabled: r.target != .none, scale: scale, accent: accent,
                modes: router.supportsModes ? PlaybackModes(shuffle: r.nowPlaying?.shuffle ?? false, repeatMode: r.nowPlaying?.repeatMode ?? .off, nextRepeat: router.nextRepeatMode) : nil
            ) { router.send($0) }
        }
    }
}

/// Artwork that brings the playing app forward when clicked, with a small app badge.
struct ArtworkButton: View {
    let nowPlaying: NowPlaying?
    let size: CGFloat
    let radius: CGFloat
    let accent: Color
    let direction: CGFloat
    @State private var hovering = false

    var body: some View {
        let id = nowPlaying?.bundleID
        Button {
            if let id { NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate() }
        } label: {
            ArtworkView(nowPlaying: nowPlaying, size: size, radius: radius, accent: accent, direction: direction, glows: true)
                .overlay {
                    // Hover hint: dim and show where a click goes.
                    ZStack {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(0.35))
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: size * 0.2, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.4), radius: 6)
                    }
                    .opacity(hovering && id != nil ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.94)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let id {
                        Image(nsImage: AppInfo.icon(id))
                            .resizable()
                            .frame(width: size * 0.2, height: size * 0.2)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                            .offset(x: size * 0.05, y: size * 0.05)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 12, y: 5)
                .scaleEffect(hovering ? 1.025 : 1)
        }
        .buttonStyle(PressableCapsuleStyle())
        .onHover { h in withAnimation(Theme.snappy) { hovering = h } }
        .help(id.map { "Open \(AppInfo.name($0))" } ?? "")
    }
}

struct SourceBadge: View {
    @ObservedObject var router: MediaRouter
    let pinnedID: String?
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        let r = router.resolution
        let id = r.nowPlaying?.bundleID ?? pinnedID
        let pinned = pinnedID != nil

        Button(action: onTap) {
            HStack(spacing: 5) {
                Group {
                    if let id {
                        Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 14, height: 14)
                        Text(AppInfo.name(id))
                    } else {
                        Image(systemName: "music.note.list").font(.system(size: 10, weight: .semibold))
                        Text("Automatic")
                    }
                }
                .id(id ?? "")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                Image(systemName: pinned ? "pin.fill" : "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white.opacity(pinned ? 0.8 : 0.45))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(hovering ? 0.14 : 0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Theme.snappy, value: id)
        .animation(Theme.snappy, value: pinned)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help("Choose which app SideTune controls")
    }
}

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        HeaderButton(systemImage: "xmark", help: "Hide (⌥⌘M to bring back)", action: action)
    }
}

/// Small round button in the card's header.
struct HeaderButton: View {
    let systemImage: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(hovering || active ? 0.95 : 0.6))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(hovering ? 0.2 : active ? 0.16 : 0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(help)
    }
}

struct PillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableCapsuleStyle())
        .frame(height: 38)
    }
}

struct PressableCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}
