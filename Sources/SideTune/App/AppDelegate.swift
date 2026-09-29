import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private lazy var router = MediaRouter(settings: settings)
    private var overlay: OverlayController!
    private var statusItem: StatusItemController!
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    /// Keeps App Nap from throttling the overlay; it's never the active app, and when napped
    /// its animations stall mid-flight until the next event.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Floating player animations"
        )
        router.start()

        overlay = OverlayController(settings: settings, router: router)
        overlay.onShowSourceMenu = { [unowned self] in SourceMenu.popUpAtMouse(router: router, settings: settings) }
        statusItem = StatusItemController(router: router, settings: settings) { [unowned self] in openSettings() }
        statusItem.attachToNotch = { [unowned self] in overlay.attachToNotch() }

        settings.$hotKeyEnabled
            .removeDuplicates()
            .sink { [unowned self] enabled in
                hotKey = enabled ? HotKey { [weak self] in self?.settings.showOverlay.toggle() } : nil
            }
            .store(in: &bag)

        // Give the media stream a beat to report before the first show, so the card
        // doesn't flash "Nothing playing" and then swap in the real track.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.overlay.showIfAllowed() }
    }

    /// Launching the app again (Finder, Spotlight) brings the overlay back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.showOverlay = true
        overlay.showIfAllowed()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        router.stop()
    }

    private func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, router: router))
            let window = NSWindow(contentViewController: host)
            window.title = "SideTune Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
