import AppKit

/// Display names and icons for player apps, cached.
@MainActor
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    private static let knownNames = [
        "com.spotify.client": "Spotify",
        "com.apple.Music": "Music",
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "org.mozilla.firefox": "Firefox",
        "company.thebrowser.Browser": "Arc",
        "com.brave.Browser": "Brave",
        "com.microsoft.edgemac": "Edge",
        "com.apple.podcasts": "Podcasts",
        "com.apple.TV": "TV",
        "org.videolan.vlc": "VLC",
    ]

    static func name(_ bundleID: String) -> String {
        if let n = names[bundleID] { return n }
        var n = knownNames[bundleID]
        if n == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            n = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        let result = n ?? bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        names[bundleID] = result
        return result
    }

    static func icon(_ bundleID: String) -> NSImage {
        if let i = icons[bundleID] { return i }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        icons[bundleID] = image
        return image
    }

    /// 16pt copy for menus.
    static func menuIcon(_ bundleID: String) -> NSImage {
        let src = icon(bundleID)
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            src.draw(in: rect)
            return true
        }
        return img
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func launch(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
