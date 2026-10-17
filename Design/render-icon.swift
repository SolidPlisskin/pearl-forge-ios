// Renders the Pearl Forge app icon (1024×1024, opaque PNG).
// Run from the Design folder:  xcrun swiftc -O -o /tmp/render-icon render-icon.swift && /tmp/render-icon ../PearlForge/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// It also writes preview-180.png and preview-87.png next to where it runs.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Pearl Forge app icon: a luminous pearl lit from below by a forge's glow,
// on deep teal, with faint rings for the voice. 1024×1024, fully opaque.
let size = 1024
let s = CGFloat(size)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}
func radial(_ g: CGGradient, at c: CGPoint, radius: CGFloat, from start: CGPoint? = nil) {
    ctx.drawRadialGradient(g, startCenter: start ?? c, startRadius: 0, endCenter: c, endRadius: radius,
                           options: [.drawsAfterEndLocation])
}

// 1. Background: deep teal fading to near-black at the bottom.
ctx.drawLinearGradient(gradient([(0, color(0x02070B)), (0.42, color(0x082A36)), (1, color(0x135A6E))]),
                       start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])

// 2. The forge: warm glow rising from below.
radial(gradient([(0, color(0xFF7A1E, 0.85)), (0.40, color(0xE04A14, 0.38)), (1, color(0x9A2A08, 0))]),
       at: CGPoint(x: s / 2, y: -s * 0.04), radius: s * 0.66)
radial(gradient([(0, color(0xFFD27A, 0.90)), (0.5, color(0xFFA040, 0.35)), (1, color(0xFF8A2A, 0))]),
       at: CGPoint(x: s / 2, y: -s * 0.06), radius: s * 0.30)

// Sparks rising from the forge.
for (x, y, radius, alpha) in [(0.40, 0.17, 0.012, 0.95), (0.58, 0.13, 0.009, 0.85), (0.47, 0.25, 0.007, 0.70),
                              (0.63, 0.22, 0.006, 0.55), (0.35, 0.28, 0.005, 0.45), (0.54, 0.31, 0.0045, 0.40)] {
    let c = CGPoint(x: s * x, y: s * y)
    radial(gradient([(0, color(0xFFF1C2, alpha)), (0.35, color(0xFFB050, alpha * 0.6)), (1, color(0xFF7A1E, 0))]),
           at: c, radius: s * radius * 3.2)
}

// 3. Voice rings around the pearl.
let center = CGPoint(x: s / 2, y: s * 0.55)
let r = s * 0.255
for (radius, alpha, width) in [(r * 1.36, 0.13, s * 0.010), (r * 1.66, 0.075, s * 0.008), (r * 1.96, 0.04, s * 0.006)] {
    ctx.setStrokeColor(color(0xE8F4F7, alpha))
    ctx.setLineWidth(width)
    ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

// 4. A soft halo so the pearl lifts off the background.
radial(gradient([(0.0, color(0xFFF3E0, 0.0)), (0.72, color(0xFFE7C2, 0.0)), (0.80, color(0xFFE7C2, 0.16)), (1, color(0xFFE7C2, 0))]),
       at: center, radius: r * 1.28)

// 5. The pearl.
let pearlRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
ctx.saveGState()
ctx.addEllipse(in: pearlRect)
ctx.clip()
// Body: light from the upper left, cooling toward the edge.
radial(gradient([(0, color(0xFFFFFF)), (0.18, color(0xFDF8F1)), (0.45, color(0xEDE5EC)), (0.72, color(0xC9CBD8)), (0.92, color(0x99A1B4)), (1, color(0x7A8398))]),
       at: center, radius: r, from: CGPoint(x: center.x - r * 0.34, y: center.y + r * 0.38))
// Iridescent sheen: faint pink and aqua across the surface.
ctx.setBlendMode(.softLight)
ctx.drawLinearGradient(gradient([(0, color(0xFF9EC4, 0.55)), (0.5, color(0xFFFFFF, 0.0)), (1, color(0x7FE3E6, 0.55))]),
                       start: CGPoint(x: center.x - r, y: center.y + r), end: CGPoint(x: center.x + r, y: center.y - r), options: [])
radial(gradient([(0, color(0xFF8FB8, 0.0)), (0.62, color(0xFF8FB8, 0.0)), (0.92, color(0xFF8FB8, 0.55)), (1, color(0xFF8FB8, 0.2))]),
       at: CGPoint(x: center.x + r * 0.18, y: center.y), radius: r * 1.02)
radial(gradient([(0, color(0x6FE0D8, 0.0)), (0.66, color(0x6FE0D8, 0.0)), (0.93, color(0x6FE0D8, 0.5)), (1, color(0x6FE0D8, 0.2))]),
       at: CGPoint(x: center.x - r * 0.20, y: center.y + r * 0.05), radius: r * 1.02)
ctx.setBlendMode(.normal)
// The forge's warm light catching the underside.
radial(gradient([(0, color(0xFF9A40, 0.85)), (0.55, color(0xFF7A2A, 0.30)), (1, color(0xFF7A2A, 0))]),
       at: CGPoint(x: center.x + r * 0.05, y: center.y - r * 1.15), radius: r * 1.05)
// Edge shading for roundness.
radial(gradient([(0, color(0x1A2433, 0)), (0.82, color(0x1A2433, 0)), (1, color(0x1A2433, 0.30))]), at: center, radius: r)
ctx.restoreGState()

// Specular highlight.
ctx.saveGState()
ctx.translateBy(x: center.x - r * 0.36, y: center.y + r * 0.42)
ctx.rotate(by: .pi / 6)
ctx.scaleBy(x: 1.0, y: 0.62)
radial(gradient([(0, color(0xFFFFFF, 1.0)), (0.30, color(0xFFFFFF, 0.85)), (0.60, color(0xFFFFFF, 0.25)), (1, color(0xFFFFFF, 0))]),
       at: .zero, radius: r * 0.30)
ctx.restoreGState()
// A small second glint.
radial(gradient([(0, color(0xFFFFFF, 0.55)), (1, color(0xFFFFFF, 0))]),
       at: CGPoint(x: center.x + r * 0.42, y: center.y - r * 0.38), radius: r * 0.12)

// Save.
let image = ctx.makeImage()!
func write(_ image: CGImage, to path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
write(image, to: CommandLine.arguments[1])

// Small previews, as the icon appears on the home screen and in Settings.
for px in [180, 87] {
    let small = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    small.interpolationQuality = .high
    small.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    write(small.makeImage()!, to: "preview-\(px).png")
}
