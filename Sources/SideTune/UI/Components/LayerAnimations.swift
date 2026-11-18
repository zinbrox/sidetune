import AppKit
import CoreImage
import SwiftUI

// Continuous animations run as Core Animation layer animations: the render server drives them,
// so SwiftUI doesn't re-render the view graph every frame (a SwiftUI TimelineView did, at ~10–15% CPU).

// MARK: Pausable layer clock

private extension CALayer {
    /// Freezes or resumes every animation in this layer's subtree, keeping its current phase.
    func setAnimationsRunning(_ running: Bool) {
        if running {
            guard speed == 0 else { return }
            let paused = timeOffset
            speed = 1
            timeOffset = 0
            beginTime = 0
            beginTime = convertTime(CACurrentMediaTime(), from: nil) - paused
        } else {
            guard speed != 0 else { return }
            let now = convertTime(CACurrentMediaTime(), from: nil)
            speed = 0
            timeOffset = now
        }
    }
}

// MARK: Drifting artwork

/// The artwork blurred, saturated and scaled up, slowly rotating and drifting while `animating`.
struct DriftingArtwork: NSViewRepresentable {
    let image: NSImage
    let key: String
    let animating: Bool

    func makeNSView(context: Context) -> DriftingArtworkView { DriftingArtworkView() }

    func updateNSView(_ view: DriftingArtworkView, context: Context) {
        view.setImage(image, key: key)
        view.setAnimating(animating && !Theme.reduceMotion)
    }
}

final class DriftingArtworkView: NSView {
    /// Pauses/resumes the whole subtree.
    private let clock = CALayer()
    /// Drifts (additive position animations).
    private let drift = CALayer()
    /// Holds the image and rotates.
    private let content = CALayer()
    private var key: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        content.contentsGravity = .resizeAspectFill
        drift.addSublayer(content)
        clock.addSublayer(drift)
        layer?.addSublayer(clock)
        addAnimations()
        clock.setAnimationsRunning(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clock.frame = bounds
        drift.frame = bounds
        // Fill the container, then scale up so rotation never shows the corners.
        let side = max(bounds.width, bounds.height) * 1.7
        content.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        content.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func setImage(_ image: NSImage, key: String) {
        guard key != self.key else { return }
        self.key = key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.contents = Self.blurred(image, key: key)
        CATransaction.commit()
    }

    func setAnimating(_ on: Bool) { clock.setAnimationsRunning(on) }

    private func addAnimations() {
        let slow = Theme.slowdown
        // One full clockwise turn every 90s (y-up layer space, so negative is clockwise).
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = 90 * slow
        spin.repeatCount = .infinity
        content.add(spin, forKey: "spin")

        // Ease-in-out back and forth reads as a sine; unrelated periods keep it from looping visibly.
        func sway(_ path: String, amplitude: Double, period: Double) -> CABasicAnimation {
            let a = CABasicAnimation(keyPath: path)
            a.isAdditive = true
            a.fromValue = -amplitude
            a.toValue = amplitude
            a.duration = period / 2 * slow
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return a
        }
        drift.add(sway("position.x", amplitude: 18, period: 2 * .pi / 0.23), forKey: "swayX")
        drift.add(sway("position.y", amplitude: 10, period: 2 * .pi / 0.17), forKey: "swayY")
    }

    // MARK: Blur, once per track

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static var cache: (key: String, image: CGImage?)?

    /// Small, blurred, saturated copy. The layer scales it up; a blur hides the low resolution.
    static func blurred(_ image: NSImage, key: String) -> CGImage? {
        if let cache, cache.key == key { return cache.image }
        var result: CGImage?
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let side: CGFloat = 160
            let input = CIImage(cgImage: cg)
            let scale = side / max(input.extent.width, input.extent.height)
            let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let extent = small.extent
            // Radius 42pt on a ~650pt drawn image ≈ 6.5% of its width.
            let out = small.clampedToExtent()
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.7])
                .applyingGaussianBlur(sigma: Double(side) * 0.065)
                .cropped(to: extent)
            result = ciContext.createCGImage(out, from: extent)
        }
        cache = (key, result)
        return result
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
        AudioBarsLayer(isPlaying: isPlaying, color: NSColor(color), barCount: barCount, height: height, barWidth: barWidth)
            .frame(width: CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barWidth * 0.75, height: height)
    }
}

private struct AudioBarsLayer: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor
    let barCount: Int
    let height: CGFloat
    let barWidth: CGFloat

    func makeNSView(context: Context) -> AudioBarsView { AudioBarsView(barCount: barCount, height: height, barWidth: barWidth) }

    func updateNSView(_ view: AudioBarsView, context: Context) {
        view.setColor(color)
        view.setPlaying(isPlaying)
    }
}

final class AudioBarsView: NSView {
    private let bars: [CALayer]
    private let height: CGFloat
    private let barWidth: CGFloat
    private var playing: Bool?
    private var color: NSColor?

    init(barCount: Int, height: CGFloat, barWidth: CGFloat) {
        self.height = height
        self.barWidth = barWidth
        bars = (0..<barCount).map { _ in CALayer() }
        super.init(frame: .zero)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: barWidth)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.position = CGPoint(x: barWidth / 2 + CGFloat(i) * barWidth * 1.75, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func setColor(_ c: NSColor) {
        guard c != color else { return }
        let first = color == nil
        color = c
        CATransaction.begin()
        CATransaction.setDisableActions(first)
        CATransaction.setAnimationDuration(0.6 * Theme.slowdown)
        for bar in bars { bar.backgroundColor = c.cgColor }
        CATransaction.commit()
    }

    func setPlaying(_ on: Bool) {
        guard on != playing else { return }
        let first = playing == nil
        playing = on
        CATransaction.begin()
        CATransaction.setDisableActions(first)
        CATransaction.setAnimationDuration(0.12 * Theme.slowdown)
        for (i, bar) in bars.enumerated() {
            if on {
                bar.add(dance(i), forKey: "dance")
            } else {
                // Settle from wherever the bar is now.
                let current = bar.presentation()?.bounds.height ?? barWidth
                bar.removeAnimation(forKey: "dance")
                bar.bounds.size.height = current
                bar.bounds.size.height = barWidth
            }
        }
        CATransaction.commit()
    }

    /// Two sines at unrelated rates per bar reads as organic rather than looping; the loop is 8s
    /// and its seam is spread over the whole loop so it's invisible.
    private func dance(_ i: Int) -> CAKeyframeAnimation {
        let loop = 8.0, steps = 160
        let d = Double(i)
        let f = { (t: Double) in 0.5 + 0.3 * sin(t * (5.1 + d * 1.7) + d * 1.3) + 0.2 * sin(t * (8.3 - d * 0.9) + d * 2.1) }
        let seam = f(0) - f(loop)
        let values: [CGFloat] = (0...steps).map { s in
            let t = loop * Double(s) / Double(steps)
            let v = (f(t) + seam * t / loop).clamped(to: 0...1)
            return barWidth + (height - barWidth) * CGFloat(v)
        }
        let a = CAKeyframeAnimation(keyPath: "bounds.size.height")
        a.values = values
        a.duration = loop * Theme.slowdown
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.beginTime = CACurrentMediaTime() - Double.random(in: 0..<loop)
        return a
    }
}
