import SwiftUI

/// Player shown in the menu bar popover.
struct MiniPlayer: View {
    @ObservedObject var router: MediaRouter
    @ObservedObject var settings: Settings
    let showSourceMenu: () -> Void
    let openSettings: () -> Void

    var body: some View {
        let r = router.resolution
        let np = r.nowPlaying
        let accent = Color(nsColor: router.accent)
        let text = PlayerText(r)

        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ArtworkView(nowPlaying: np, size: 64, radius: 12, accent: accent, direction: router.trackDirection, glows: true)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                TrackText(text: text, accent: accent, direction: router.trackDirection, titleSize: 14, subtitleSize: 12)
            }

            ScrubBar(nowPlaying: np, accent: accent, enabled: r.target != .none, stacked: true) { router.send(.seek($0)) }

            TransportControls(
                isPlaying: np?.isPlaying ?? false, enabled: r.target != .none, scale: 1.1, accent: accent,
                modes: router.supportsModes ? PlaybackModes(shuffle: np?.shuffle ?? false, repeatMode: np?.repeatMode ?? .off, nextRepeat: router.nextRepeatMode) : nil
            ) { router.send($0) }

            HStack(spacing: 8) {
                SourceBadge(router: router, pinnedID: settings.pinnedBundleID, onTap: showSourceMenu)
                Spacer()
                ToolbarIcon(
                    systemImage: settings.showOverlay ? "rectangle.righthalf.inset.filled" : "rectangle.righthalf.inset.filled.arrow.right",
                    help: settings.showOverlay ? "Hide floating player" : "Show floating player",
                    active: settings.showOverlay
                ) { settings.showOverlay.toggle() }
                ToolbarIcon(systemImage: "gearshape", help: "Settings", active: false, action: openSettings)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            CardBackground(
                artwork: settings.tintWithArtwork ? np?.artwork : nil,
                artworkKey: np?.artworkKey ?? "", accent: accent,
                isPlaying: np?.isPlaying ?? false
            )
        )
        .environment(\.colorScheme, .dark)
    }
}

struct ToolbarIcon: View {
    let systemImage: String
    let help: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(active ? 0.9 : 0.6))
                .frame(width: 26, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(hovering ? 0.14 : active ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(help)
    }
}
