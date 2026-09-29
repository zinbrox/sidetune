// Renders SideTune's app icon into an .iconset directory: a dark glassy squircle
// with a player tab docked to its right edge, glowing equalizer bars inside.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // Squircle body (Apple grid: 824pt tile centered in 1024).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    body.fill()
    ctx.restoreGState()

    body.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.24, green: 0.13, blue: 0.42, alpha: 1),
        NSColor(calibratedRed: 0.55, green: 0.22, blue: 0.55, alpha: 1),
    ])!.draw(in: tile, angle: -60)

    // Soft light bloom top-left.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: CGPoint(x: 330, y: 780), radius: 0, toCenter: CGPoint(x: 330, y: 780), radius: 520, options: [])

    // The docked tab, hanging off the right edge.
    let tab = CGRect(x: 600, y: 262, width: 420, height: 500)
    let tabPath = NSBezierPath(roundedRect: tab, xRadius: 110, yRadius: 110)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -10, height: -16), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor(calibratedWhite: 0.07, alpha: 0.85).setFill()
    tabPath.fill()
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.14).setStroke()
    tabPath.lineWidth = 5
    tabPath.stroke()

    // Artwork square in the tab.
    let art = CGRect(x: 668, y: 548, width: 150, height: 150)
    let artPath = NSBezierPath(roundedRect: art, xRadius: 36, yRadius: 36)
    ctx.saveGState()
    artPath.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.35, alpha: 1),
        NSColor(calibratedRed: 0.95, green: 0.3, blue: 0.6, alpha: 1),
    ])!.draw(in: art, angle: -45)
    ctx.restoreGState()

    // Equalizer bars below the artwork.
    let accent = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.78, alpha: 1)
    let heights: [CGFloat] = [120, 200, 150, 90]
    for (i, h) in heights.enumerated() {
        let r = CGRect(x: 676 + CGFloat(i) * 38, y: 400 - h / 2, width: 22, height: h)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 26, color: accent.withAlphaComponent(0.9).cgColor)
        accent.setFill()
        NSBezierPath(roundedRect: r, xRadius: 11, yRadius: 11).fill()
        ctx.restoreGState()
    }

    // Motion hint: the tab slid in from the edge.
    for (i, y) in [390.0, 460.0, 530.0].enumerated() {
        let w = 150.0 - Double(i) * 30
        let line = NSBezierPath(roundedRect: CGRect(x: 520 - w, y: y, width: w, height: 16), xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.16 - Double(i) * 0.04).setFill()
        line.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
