import AppKit

/// NSMenuItem that runs a closure.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, image: NSImage? = nil, state: NSControl.StateValue = .off, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.image = image
        self.state = state
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

/// "Which app should SideTune control?" menu, shared by the overlay and the menu bar.
@MainActor
enum SourceMenu {
    static func items(router: MediaRouter, settings: Settings) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let pinned = settings.pinnedBundleID

        let header = NSMenuItem(title: "Control", action: nil, keyEquivalent: "")
        header.isEnabled = false
        items.append(header)

        let auto = BlockMenuItem(
            "Automatic",
            image: NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil),
            state: pinned == nil ? .on : .off
        ) { router.pin(nil) }
        auto.toolTip = "Follow whatever is playing"
        items.append(auto)
        items.append(.separator())

        if router.sources.isEmpty {
            let none = NSMenuItem(title: "No players detected yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            items.append(none)
        }
        for source in router.sources {
            let item = BlockMenuItem(
                "Pin to \(source.name)",
                image: AppInfo.menuIcon(source.bundleID),
                state: pinned == source.bundleID ? .on : .off
            ) { router.pin(source.bundleID) }
            item.toolTip = source.canTargetControl
                ? "Controls stay on \(source.name) even if another app starts playing."
                : "\(source.name) can only be controlled while it's the active player."
            items.append(item)
        }

        items.append(.separator())
        let note = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        note.attributedTitle = NSAttributedString(
            string: "Pinning to Spotify or Music keeps the controls\non that app when something else starts playing.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        note.isEnabled = false
        items.append(note)
        return items
    }

    static func menu(router: MediaRouter, settings: Settings) -> NSMenu {
        let menu = NSMenu()
        items(router: router, settings: settings).forEach(menu.addItem)
        return menu
    }

    static func popUpAtMouse(router: MediaRouter, settings: Settings) {
        menu(router: router, settings: settings).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
