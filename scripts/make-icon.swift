// Generates AppIcon.icns: a coral atoll — sand ring with two channel gaps
// around a turquoise lagoon, on deep ocean. Run: swift scripts/make-icon.swift
import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon canvas: rounded rect inset ~100 on 1024, radius ~185
let tile = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
    xRadius: 185, yRadius: 185)
tile.setClip()

// deep ocean
NSGradient(starting: rgb(0x0E2E42), ending: rgb(0x071825))!
    .draw(in: tile, angle: -90)

let c = NSPoint(x: S / 2, y: S / 2)

// shallow-water halo around the reef
let halo = NSGradient(
    colorsAndLocations: (rgb(0x2CB9AF, 0.28), 0.0), (rgb(0x2CB9AF, 0.0), 1.0))!
halo.draw(
    in: NSBezierPath(ovalIn: NSRect(x: c.x - 400, y: c.y - 400, width: 800, height: 800)),
    relativeCenterPosition: .zero)

// lagoon
let lagoon = NSBezierPath(ovalIn: NSRect(x: c.x - 240, y: c.y - 240, width: 480, height: 480))
NSGradient(
    colorsAndLocations: (rgb(0x93EBDD), 0.0), (rgb(0x2CB9AF), 1.0))!
    .draw(in: lagoon, relativeCenterPosition: NSPoint(x: -0.15, y: 0.2))

// sand ring, two channel gaps (start/end angles in degrees)
rgb(0xF0E1BF).setStroke()
for (a0, a1) in [(80.0, 210.0), (228.0, 350.0)] {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: c, radius: 272, startAngle: a0, endAngle: a1)
    arc.lineWidth = 74
    arc.lineCapStyle = .round
    arc.stroke()
}

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let out = "scripts/icon_1024.png"
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
