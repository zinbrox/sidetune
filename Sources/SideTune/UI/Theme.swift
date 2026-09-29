import AppKit
import SwiftUI

enum Theme {
    static let fallbackAccent = NSColor(calibratedRed: 0.62, green: 0.55, blue: 1.0, alpha: 1)

    /// A vivid color from the artwork, bright enough to read on the dark card.
    static func accent(from image: NSImage?) -> NSColor {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return fallbackAccent }
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return fallbackAccent }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let pr = Double(pixels[i]) / 255, pg = Double(pixels[i + 1]) / 255, pb = Double(pixels[i + 2]) / 255
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let sat = maxC > 0 ? (maxC - minC) / maxC : 0
            // Favor saturated, reasonably bright pixels; keep a floor so gray art still averages.
            let weight = sat * sat * maxC + 0.01
            r += pr * weight; g += pg * weight; b += pb * weight; total += weight
        }
        let avg = NSColor(calibratedRed: r / total, green: g / total, blue: b / total, alpha: 1)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
        if sat < 0.12 { return NSColor(calibratedWhite: 0.92, alpha: 1) }
        return NSColor(calibratedHue: hue, saturation: min(max(sat, 0.45), 0.8), brightness: max(bri, 0.88), alpha: 1)
    }

    /// Slow-motion factor for recording the demo GIF (scripts/screenshots.sh); 1 in the app.
    static var slowdown: Double = 1
    /// Animation clock, slowed along with `slowdown`.
    static func clock(_ date: Date) -> TimeInterval { date.timeIntervalSinceReferenceDate / slowdown }
    static func timed(_ a: Animation) -> Animation { slowdown == 1 ? a : a.speed(1 / slowdown) }
    /// When slow motion started; `playbackDate` runs slowed from here.
    static var slowdownStart = Date()
    /// Wall-clock time for playback position, slowed along with animations while recording.
    static func playbackDate(_ date: Date) -> Date {
        slowdown == 1 ? date : slowdownStart.addingTimeInterval(date.timeIntervalSince(slowdownStart) / slowdown)
    }

    /// Springs, or quick fades when the user asked for reduced motion.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var morph: Animation { timed(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.8)) }
    static var snappy: Animation { timed(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.72)) }
}

/// Behind-window blur that stays active even though the overlay window is never key.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    /// The screenshot renderer blurs its own wallpaper instead of the real desktop.
    static var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = Self.blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
