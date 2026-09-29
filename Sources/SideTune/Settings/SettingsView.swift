import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var router: MediaRouter
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Where it appears") {
                Toggle("Floating player", isOn: $settings.showOverlay)
                Toggle("Menu bar icon", isOn: $settings.showMenuBarItem)
                Toggle("Show track title in menu bar", isOn: $settings.menuBarShowsTitle)
                    .disabled(!settings.showMenuBarItem)
                Toggle("Show over full-screen apps", isOn: $settings.overFullScreen)
                Toggle("Hide when nothing is playing", isOn: $settings.hideWhenIdle)
            }

            Section {
                Toggle("Snap to screen edges", isOn: $settings.magnetEnabled)
                LabeledContent("Magnet strength") {
                    Slider(value: $settings.snapDistance, in: 16...80) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Light").font(.caption)
                    } maximumValueLabel: {
                        Text("Strong").font(.caption)
                    }
                    .frame(width: 200)
                }
                .disabled(!settings.magnetEnabled)
                if OverlayController.hasNotchScreen {
                    Toggle("Attach beside the notch when docked near it", isOn: $settings.attachToNotch)
                        .disabled(!settings.magnetEnabled)
                }
                Toggle("Collapse into a tab when docked", isOn: $settings.autoCollapse)
                LabeledContent("Expand on hover after") {
                    Picker("", selection: $settings.hoverDelay) {
                        Text("Instantly").tag(0.0)
                        Text("A moment").tag(0.12)
                        Text("Half a second").tag(0.5)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                .disabled(!settings.autoCollapse)
            } header: {
                Text("Docking")
            } footer: {
                Text("Drag the player near any edge to dock it; hold ⌥ while dragging to place it anywhere without snapping. Drop it at the top next to the notch to tuck it in beside the notch. Throw it off-screen to hide it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Control", selection: Binding(
                    get: { settings.pinnedBundleID ?? "" },
                    set: { settings.pinnedBundleID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Automatic").tag("")
                    ForEach(router.sources) { s in
                        Text(s.name).tag(s.bundleID)
                    }
                }
            } header: {
                Text("Player")
            } footer: {
                Text("Pin Spotify or Music to keep the controls on that app even when a browser or another app starts playing. Other apps can be pinned too, but they're only controllable while they're the active player.")
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                LabeledContent("Player size") {
                    Slider(value: $settings.cardScale, in: Double(OverlayMetrics.scaleRange.lowerBound)...Double(OverlayMetrics.scaleRange.upperBound)) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "rectangle.inset.filled").font(.caption2)
                    } maximumValueLabel: {
                        Image(systemName: "rectangle.inset.filled").font(.body)
                    }
                    .frame(width: 200)
                }
                Toggle("Tint with album artwork", isOn: $settings.tintWithArtwork)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("⌥⌘M shows and hides the floating player", isOn: $settings.hotKeyEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription). Move SideTune to /Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
