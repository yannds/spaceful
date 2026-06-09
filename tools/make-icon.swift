#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Generates the Spaceful app icon — a single, pared-down "sunburst" ring in calm shades
// of one blue, on a light squircle tile, with a clean white core (the "free space").
// Reads both as a disk-space breakdown and as a disk platter. Pure CoreGraphics, no deps.
// Run: swift tools/make-icon.swift   (assembles Spaceful.iconset + docs/icon-preview.png)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: a).cgColor
}

// Single ring of blue tints, largest slice first.
let segments: [(frac: CGFloat, color: CGColor)] = [
    (0.30, hsb(0.60, 0.70, 0.95)),
    (0.24, hsb(0.58, 0.55, 0.92)),
    (0.18, hsb(0.62, 0.42, 0.88)),
    (0.16, hsb(0.56, 0.30, 0.92)),
    (0.12, hsb(0.60, 0.18, 0.96)),
]

func makeIcon(size s: CGFloat) -> CGImage {
    let px = Int(s)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Squircle tile with transparent corners + soft shadow.
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.035,
                  color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.addPath(tile); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Light vertical gradient background.
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [hsb(0.60, 0.10, 0.99), hsb(0.60, 0.16, 0.92)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Sunburst ring.
    let center = CGPoint(x: s / 2, y: s / 2)
    let inner = s * 0.205, outer = s * 0.355
    let gapDeg: CGFloat = 3.2
    var cursor: CGFloat = 90
    for seg in segments {
        let sweep = seg.frac * 360
        let a0 = (cursor + gapDeg / 2) * .pi / 180
        let a1 = (cursor + sweep - gapDeg / 2) * .pi / 180
        let path = CGMutablePath()
        path.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        path.closeSubpath()
        ctx.addPath(path); ctx.setFillColor(seg.color); ctx.fillPath()
        cursor += sweep
    }

    // White core with a faint hairline so it reads as a hollow centre.
    let hole = CGRect(x: center.x - s * 0.155, y: center.y - s * 0.155, width: s * 0.31, height: s * 0.31)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: hole)
    ctx.setStrokeColor(hsb(0.60, 0.14, 0.84))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokeEllipse(in: hole.insetBy(dx: s * 0.004, dy: s * 0.004))

    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Spaceful.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, size) in entries {
    let img = cache[Int(size)] ?? makeIcon(size: size)
    cache[Int(size)] = img
    writePNG(img, to: iconset.appendingPathComponent("\(name).png"))
}
writePNG(cache[512] ?? makeIcon(size: 512), to: root.appendingPathComponent("docs/icon-preview.png"))
print("✓ Iconset + preview generated")
