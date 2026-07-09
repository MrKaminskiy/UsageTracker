#!/usr/bin/env swift
// Generates the UsageTracker app icon (modern gauge, indigo→violet gradient, no text).
// Usage:
//   swift scripts/make_icon.swift preview <out.png> [size]   -> single PNG for review
//   swift scripts/make_icon.swift iconset <AppIcon.icns>      -> full .icns via iconutil
import AppKit

// ---- Palette -------------------------------------------------------------
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}
let gradTop    = rgb(122, 99, 255)   // bright indigo-violet (top-left)
let gradBottom = rgb(67, 24, 168)    // deep violet (bottom-right)
let deepViolet = rgb(60, 20, 150)    // hub inner

// ---- Drawing (all geometry in a 1024 design space) -----------------------
func draw(_ cg: CGContext, size: CGFloat) {
    let s = size / 1024
    cg.scaleBy(x: s, y: s)
    cg.setAllowsAntialiasing(true)

    let inset: CGFloat = 100
    let tile = CGRect(x: inset, y: inset, width: 1024 - 2*inset, height: 1024 - 2*inset)
    let radius: CGFloat = 190
    let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow beneath the tile (for the Dock)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 44,
                 color: NSColor(white: 0, alpha: 0.30).cgColor)
    cg.addPath(tilePath); cg.setFillColor(NSColor.black.cgColor); cg.fillPath()
    cg.restoreGState()

    // Gradient fill, clipped to the tile
    cg.saveGState()
    cg.addPath(tilePath); cg.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space,
                        colors: [gradTop.cgColor, gradBottom.cgColor] as CFArray,
                        locations: [0, 1])!
    cg.drawLinearGradient(bg,
                          start: CGPoint(x: tile.minX, y: tile.maxY),
                          end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // Soft top glow for depth
    let glow = CGGradient(colorsSpace: space,
                          colors: [NSColor(white: 1, alpha: 0.20).cgColor,
                                   NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 760), startRadius: 0,
                          endCenter: CGPoint(x: 512, y: 760), endRadius: 560, options: [])
    cg.restoreGState()

    // ---- Gauge -----------------------------------------------------------
    let gc = CGPoint(x: 512, y: 400)
    let R: CGFloat = 250
    let lw: CGFloat = 58
    let frac: CGFloat = 0.70
    cg.setLineCap(.round)
    cg.setLineWidth(lw)

    // Track (faint) — top semicircle from 180° to 0°
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.22).cgColor)
    cg.addArc(center: gc, radius: R, startAngle: .pi, endAngle: 0, clockwise: true)
    cg.strokePath()

    // Progress (bright) — first `frac` of the sweep
    let endA = CGFloat.pi - frac * CGFloat.pi
    cg.setStrokeColor(NSColor.white.cgColor)
    cg.addArc(center: gc, radius: R, startAngle: .pi, endAngle: endA, clockwise: true)
    cg.strokePath()

    // Needle pointing to the progress end
    let ang = endA
    let Ln: CGFloat = 236, tailLn: CGFloat = 52, baseHalf: CGFloat = 30
    let dir = CGPoint(x: cos(ang), y: sin(ang))
    let perp = CGPoint(x: cos(ang + .pi/2), y: sin(ang + .pi/2))
    let tip  = CGPoint(x: gc.x + Ln*dir.x,     y: gc.y + Ln*dir.y)
    let tail = CGPoint(x: gc.x - tailLn*dir.x, y: gc.y - tailLn*dir.y)
    let b1   = CGPoint(x: gc.x + baseHalf*perp.x, y: gc.y + baseHalf*perp.y)
    let b2   = CGPoint(x: gc.x - baseHalf*perp.x, y: gc.y - baseHalf*perp.y)
    let needle = CGMutablePath()
    needle.move(to: tip); needle.addLine(to: b1)
    needle.addLine(to: tail); needle.addLine(to: b2); needle.closeSubpath()
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                 color: NSColor(white: 0, alpha: 0.35).cgColor)
    cg.addPath(needle); cg.setFillColor(NSColor.white.cgColor); cg.fillPath()
    cg.restoreGState()

    // Hub
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(x: gc.x-50, y: gc.y-50, width: 100, height: 100))
    cg.setFillColor(deepViolet.cgColor)
    cg.fillEllipse(in: CGRect(x: gc.x-23, y: gc.y-23, width: 46, height: 46))
}

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext, size: CGFloat(size))
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// ---- CLI -----------------------------------------------------------------
let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write("usage: make_icon.swift preview|iconset <out> [size]\n".data(using: .utf8)!); exit(1) }
let mode = args[1], out = args[2]

switch mode {
case "preview":
    let size = args.count >= 4 ? Int(args[3])! : 1024
    writePNG(render(size: size), to: out)
    print("wrote \(out) @ \(size)px")
case "iconset":
    let tmp = NSTemporaryDirectory() + "AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: tmp)
    try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    let specs: [(Int, String)] = [
        (16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),
        (128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),
        (512,"icon_512x512"),(1024,"icon_512x512@2x")]
    for (px, name) in specs { writePNG(render(size: px), to: "\(tmp)/\(name).png") }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", tmp, "-o", out]
    try! p.run(); p.waitUntilExit()
    print("wrote \(out)")
default:
    FileHandle.standardError.write("unknown mode \(mode)\n".data(using: .utf8)!); exit(1)
}
