import Foundation

/// User preferences, persisted to UserDefaults.
@MainActor
final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var showOverlay: Bool { didSet { save(showOverlay, "showOverlay"); keepSomethingVisible(changed: \.showOverlay) } }
    @Published var showMenuBarItem: Bool { didSet { save(showMenuBarItem, "showMenuBarItem"); keepSomethingVisible(changed: \.showMenuBarItem) } }
    @Published var menuBarShowsTitle: Bool { didSet { save(menuBarShowsTitle, "menuBarShowsTitle") } }
    @Published var magnetEnabled: Bool { didSet { save(magnetEnabled, "magnetEnabled") } }
    @Published var snapDistance: Double { didSet { save(snapDistance, "snapDistance") } }
    @Published var autoCollapse: Bool { didSet { save(autoCollapse, "autoCollapse") } }
    @Published var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    @Published var overFullScreen: Bool { didSet { save(overFullScreen, "overFullScreen") } }
    @Published var hideWhenIdle: Bool { didSet { save(hideWhenIdle, "hideWhenIdle") } }
    @Published var tintWithArtwork: Bool { didSet { save(tintWithArtwork, "tintWithArtwork") } }
    @Published var hotKeyEnabled: Bool { didSet { save(hotKeyEnabled, "hotKeyEnabled") } }
    /// Docking at the top near the notch attaches the player beside it, in the menu bar row.
    @Published var attachToNotch: Bool { didSet { save(attachToNotch, "attachToNotch") } }
    /// Player size, see `OverlayMetrics.scaleRange`.
    @Published var cardScale: Double { didSet { save(cardScale, "cardScale") } }
    /// nil = Automatic (follow whatever is playing).
    @Published var pinnedBundleID: String? { didSet { defaults.set(pinnedBundleID, forKey: "pinnedBundleID") } }

    init() {
        defaults.register(defaults: [
            "showOverlay": true,
            "showMenuBarItem": true,
            "menuBarShowsTitle": false,
            "magnetEnabled": true,
            "snapDistance": 36.0,
            "autoCollapse": true,
            "hoverDelay": 0.12,
            "overFullScreen": true,
            "hideWhenIdle": false,
            "tintWithArtwork": true,
            "hotKeyEnabled": true,
            "attachToNotch": true,
            "cardScale": 1.0,
        ])
        showOverlay = defaults.bool(forKey: "showOverlay")
        showMenuBarItem = defaults.bool(forKey: "showMenuBarItem")
        menuBarShowsTitle = defaults.bool(forKey: "menuBarShowsTitle")
        magnetEnabled = defaults.bool(forKey: "magnetEnabled")
        snapDistance = defaults.double(forKey: "snapDistance")
        autoCollapse = defaults.bool(forKey: "autoCollapse")
        hoverDelay = defaults.double(forKey: "hoverDelay")
        overFullScreen = defaults.bool(forKey: "overFullScreen")
        hideWhenIdle = defaults.bool(forKey: "hideWhenIdle")
        tintWithArtwork = defaults.bool(forKey: "tintWithArtwork")
        hotKeyEnabled = defaults.bool(forKey: "hotKeyEnabled")
        attachToNotch = defaults.bool(forKey: "attachToNotch")
        cardScale = defaults.double(forKey: "cardScale")
        pinnedBundleID = defaults.string(forKey: "pinnedBundleID")
        if !showOverlay && !showMenuBarItem { showMenuBarItem = true }
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    /// Hiding both the overlay and the menu bar icon would leave no way back in,
    /// so turning one off while the other is off brings the other back.
    private func keepSomethingVisible(changed: KeyPath<Settings, Bool>) {
        guard !showOverlay && !showMenuBarItem else { return }
        if changed == \Settings.showOverlay { showMenuBarItem = true } else { showOverlay = true }
    }
}
