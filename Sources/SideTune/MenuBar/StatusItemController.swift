import AppKit
import Combine
import SwiftUI

/// Menu bar icon next to battery/Wi-Fi. Click: mini player. Right-click: menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let router: MediaRouter
    private let settings: Settings
    private let openSettings: () -> Void
    var attachToNotch: (() -> Void)?
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    private var barsTimer: Timer?
    private var barsPhase: Double = 0

    init(router: MediaRouter, settings: Settings, openSettings: @escaping () -> Void) {
        self.router = router
        self.settings = settings
        self.openSettings = openSettings
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MiniPlayer(
            router: router, settings: settings,
            showSourceMenu: { SourceMenu.popUpAtMouse(router: router, settings: settings) },
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }
        ))

        settings.$showMenuBarItem
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &bag)

        Publishers.CombineLatest(router.$resolution, settings.$menuBarShowsTitle)
            .sink { [weak self] r, showTitle in self?.refresh(r, showTitle: showTitle) }
            .store(in: &bag)
    }

    private func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.imagePosition = .imageLeading
            self.item = item
            refresh(router.resolution, showTitle: settings.menuBarShowsTitle)
        } else if !visible, let item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
            stopBars()
        }
    }

    private func refresh(_ r: Resolution, showTitle: Bool) {
        guard let button = item?.button else { return }
        let playing = r.nowPlaying?.isPlaying ?? false
        if playing { startBars() } else { stopBars(); button.image = Self.icon(playing: false, phase: 0) }

        if showTitle, let np = r.nowPlaying {
            let title = np.artist.isEmpty ? np.title : "\(np.title) · \(np.artist)"
            let short = title.count > 32 ? String(title.prefix(31)) + "…" : title
            button.attributedTitle = NSAttributedString(string: " " + short, attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
        } else {
            button.title = ""
        }
        button.toolTip = r.nowPlaying.map { "\($0.title) — \($0.artist)" } ?? "SideTune"
    }

    /// Menu bar glyph: animated equalizer bars while playing, a note otherwise.
    private static func icon(playing: Bool, phase: Double) -> NSImage {
        guard playing else {
            let img = NSImage(systemSymbolName: "music.note", accessibilityDescription: "SideTune") ?? NSImage()
            img.isTemplate = true
            return img
        }
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()
            for i in 0..<4 {
                let d = Double(i)
                let v = 0.5 + 0.3 * sin(phase * (4.7 + d * 1.6) + d * 1.3) + 0.2 * sin(phase * (7.9 - d) + d * 2.2)
                let h = 3 + 10 * CGFloat(v.clamped(to: 0...1))
                let rect = NSRect(x: 1.5 + CGFloat(i) * 3.5, y: (16 - h) / 2, width: 2.2, height: h)
                NSBezierPath(roundedRect: rect, xRadius: 1.1, yRadius: 1.1).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    private func startBars() {
        guard barsTimer == nil, !Theme.reduceMotion else {
            if Theme.reduceMotion { item?.button?.image = Self.icon(playing: true, phase: 1) }
            return
        }
        let t = Timer(timeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.barsPhase += 1.0 / 12
                self.item?.button?.image = Self.icon(playing: true, phase: self.barsPhase)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        barsTimer = t
    }

    private func stopBars() {
        barsTimer?.invalidate()
        barsTimer = nil
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showMenu() {
        guard let item else { return }
        let menu = NSMenu()
        menu.addItem(BlockMenuItem(settings.showOverlay ? "Hide Floating Player" : "Show Floating Player") { [weak self] in
            self?.settings.showOverlay.toggle()
        })
        if OverlayController.hasNotchScreen {
            menu.addItem(BlockMenuItem("Attach Beside Notch") { [weak self] in self?.attachToNotch?() })
        }
        let sizeItem = NSMenuItem(title: "Player Size", action: nil, keyEquivalent: "")
        let sizes = NSMenu()
        for (name, value) in [("Small", 0.85), ("Medium", 1.0), ("Large", 1.25)] {
            sizes.addItem(BlockMenuItem(name, state: abs(settings.cardScale - value) < 0.03 ? .on : .off) { [weak self] in
                self?.settings.cardScale = value
            })
        }
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(BlockMenuItem("Keep Player Expanded", state: settings.autoCollapse ? .off : .on) { [weak self] in
            self?.settings.autoCollapse.toggle()
        })
        menu.addItem(.separator())
        SourceMenu.items(router: router, settings: settings).forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem("Settings…") { [weak self] in self?.openSettings() })
        let quit = NSMenuItem(title: "Quit SideTune", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}
