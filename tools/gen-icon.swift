// gen-icon.swift — generates the Swish Strike app icon programmatically (CoreGraphics).
// License-clean by construction: no external art, same stance as the SVG heroes.
// Outputs 1024x1024 PNGs into the AppIcon.appiconset: standard, dark, tinted.
//   swift tools/gen-icon.swift
// Runs on any Mac with Command Line Tools (no Xcode required).

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let S = 1024
let outDir = "ios/SwishStrikeApp/SwishStrike/Assets.xcassets/AppIcon.appiconset"

func srgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, _ name: String) {
    let img = ctx.makeImage()!
    let url = URL(fileURLWithPath: "\(outDir)/\(name)") as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(name)") }
    print("wrote \(outDir)/\(name)")
}

// The arc the ball travels: a rising quadratic from bottom-left to the ball.
// t in 0...1; CG coordinates (y up).
func arcPoint(_ t: CGFloat) -> CGPoint {
    let p0 = CGPoint(x: 130, y: 180)          // launch, bottom-left
    let p1 = CGPoint(x: 380, y: 980)          // control, high
    let p2 = CGPoint(x: 700, y: 640)          // the ball
    let a = 1 - t
    return CGPoint(x: a * a * p0.x + 2 * a * t * p1.x + t * t * p2.x,
                   y: a * a * p0.y + 2 * a * t * p1.y + t * t * p2.y)
}

func drawIcon(ball: CGColor, ballHi: CGColor, seam: CGColor, trail: CGColor,
              bgTop: CGColor?, bgBottom: CGColor?) -> CGContext {
    let ctx = makeContext()
    // Background (nil = black for the tinted variant, which iOS recolors).
    if let top = bgTop, let bottom = bgBottom {
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(S)),
                               end: CGPoint(x: 0, y: 0), options: [])
    } else {
        ctx.setFillColor(srgb(0x000000))
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }
    // Comet trail: circles along the arc, growing toward the ball.
    let steps = 64
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps - 1)
        let p = arcPoint(t * 0.94)             // stop just short of the ball
        let r = 6 + t * 40
        ctx.setFillColor(trail.copy(alpha: 0.04 + t * 0.35)!)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }
    // Ball with a soft top-light radial gradient.
    let c = arcPoint(1), R: CGFloat = 190
    let ballGrad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [ballHi, ball] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
    ctx.clip()
    ctx.drawRadialGradient(ballGrad,
                           startCenter: CGPoint(x: c.x - 60, y: c.y + 70), startRadius: 10,
                           endCenter: c, endRadius: R * 1.25, options: [])
    // Basketball seams: one vertical arc, one horizontal.
    ctx.setStrokeColor(seam)
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: c.x - R, y: c.y + 40))
    ctx.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y + 40),
                     control: CGPoint(x: c.x, y: c.y - 90))
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: CGPoint(x: c.x - 50, y: c.y - R))
    ctx.addQuadCurve(to: CGPoint(x: c.x - 50, y: c.y + R),
                     control: CGPoint(x: c.x + 130, y: c.y))
    ctx.strokePath()
    ctx.restoreGState()
    return ctx
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Standard: brand orange on the near-black dark gradient.
save(drawIcon(ball: srgb(0xFF5A1F), ballHi: srgb(0xFF9A5C), seam: srgb(0x8A2E0D),
              trail: srgb(0xFF7A33), bgTop: srgb(0x15171C), bgBottom: srgb(0x0A0B0E)),
     "icon-1024.png")
// Dark (iOS 18): same mark, pure-dark backdrop.
save(drawIcon(ball: srgb(0xFF5A1F), ballHi: srgb(0xFF8A47), seam: srgb(0x7A2A0C),
              trail: srgb(0xFF7A33), bgTop: srgb(0x0A0B0E), bgBottom: srgb(0x050608)),
     "icon-1024-dark.png")
// Tinted (iOS 18): grayscale mark on black; the system applies the user's tint.
save(drawIcon(ball: srgb(0xBFC4CC), ballHi: srgb(0xF0F2F5), seam: srgb(0x585E66),
              trail: srgb(0xCED3DA), bgTop: nil, bgBottom: nil),
     "icon-1024-tinted.png")
print("done.")
