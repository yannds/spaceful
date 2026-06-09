#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders three *pared-down* icon directions at 512px for comparison.
// Pure CoreGraphics. Run: swift tools/make-icon-variants.swift

let cs = CGColorSpace(name: CGColorSpace.sRGB)!

func ctx(_ s: Int) -> CGContext {
    let c = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setShouldAntialias(true); c.interpolationQuality = .high
    return c
}
func hsb(_ h: CGFloat, _ sa: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(calibratedHue: h, saturation: sa, brightness: b, alpha: a).cgColor
}
func tile(_ c: CGContext, _ s: CGFloat, top: CGColor, bottom: CGColor, flatShadow: Bool) -> CGPath {
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let r = rect.width * 0.2237
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -s*0.01), blur: s*0.035,
                color: NSColor.black.withAlphaComponent(flatShadow ? 0.18 : 0.30).cgColor)
    c.addPath(path); c.setFillColor(NSColor.black.cgColor); c.fillPath()
    c.restoreGState()
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0,1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    c.restoreGState()
    return path
}
func ring(_ c: CGContext, center: CGPoint, inner: CGFloat, outer: CGFloat,
          segs: [(CGFloat, CGColor)], gapDeg: CGFloat, start: CGFloat) {
    var cur = start
    for (frac, col) in segs {
        let sweep = frac * 360
        let a0 = (cur + gapDeg/2) * .pi/180, a1 = (cur + sweep - gapDeg/2) * .pi/180
        let p = CGMutablePath()
        p.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        c.addPath(p); c.setFillColor(col); c.fillPath()
        cur += sweep
    }
}
func write(_ img: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs/\(name).png")
    let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

let S: CGFloat = 512
let center = CGPoint(x: S/2, y: S/2)

// A — single multicolour ring, flat, generous hollow.
do {
    let c = ctx(Int(S))
    _ = tile(c, S, top: hsb(0.62,0.55,0.34), bottom: hsb(0.66,0.70,0.14), flatShadow: true)
    let segs: [(CGFloat, CGColor)] = [
        (0.30, hsb(0.60,0.62,0.97)), (0.24, hsb(0.10,0.74,0.98)),
        (0.18, hsb(0.78,0.48,0.92)), (0.16, hsb(0.42,0.58,0.86)),
        (0.12, hsb(0.95,0.60,0.96)),
    ]
    ring(c, center: center, inner: S*0.205, outer: S*0.355, segs: segs, gapDeg: 3.2, start: 90)
    c.setFillColor(hsb(0.62,0.10,0.98)); c.fillEllipse(in: CGRect(x: center.x-S*0.155, y: center.y-S*0.155, width: S*0.31, height: S*0.31))
    write(c.makeImage()!, "variant-a")
}

// B — monochrome blue tints, flat, light background.
do {
    let c = ctx(Int(S))
    _ = tile(c, S, top: hsb(0.60,0.10,0.99), bottom: hsb(0.60,0.16,0.92), flatShadow: true)
    let blue: [(CGFloat,CGColor)] = [
        (0.30, hsb(0.60,0.70,0.95)), (0.24, hsb(0.58,0.55,0.92)),
        (0.18, hsb(0.62,0.42,0.88)), (0.16, hsb(0.56,0.30,0.92)),
        (0.12, hsb(0.60,0.18,0.96)),
    ]
    ring(c, center: center, inner: S*0.205, outer: S*0.355, segs: blue, gapDeg: 3.2, start: 90)
    c.setFillColor(NSColor.white.cgColor); c.fillEllipse(in: CGRect(x: center.x-S*0.155, y: center.y-S*0.155, width: S*0.31, height: S*0.31))
    write(c.makeImage()!, "variant-b")
}

// C — gauge: single accent arc on a track, rounded caps. Ultra minimal.
do {
    let c = ctx(Int(S))
    _ = tile(c, S, top: hsb(0.62,0.50,0.30), bottom: hsb(0.66,0.66,0.13), flatShadow: true)
    let radius = S*0.27, lw = S*0.085
    c.setLineWidth(lw); c.setLineCap(.round)
    // track
    let track = CGMutablePath()
    track.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    c.addPath(track); c.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor); c.strokePath()
    // accent arc ~ 68% usage, top start, clockwise
    let startA: CGFloat = 90 * .pi/180
    let endA: CGFloat = (90 - 0.68*360) * .pi/180
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: startA, endAngle: endA, clockwise: true)
    c.addPath(arc)
    c.replacePathWithStrokedPath()
    c.clip()
    let g = CGGradient(colorsSpace: cs, colors: [hsb(0.50,0.60,0.96), hsb(0.60,0.66,0.97)] as CFArray, locations: [0,1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    write(c.makeImage()!, "variant-c")
}

print("✓ variants a/b/c → docs/")
