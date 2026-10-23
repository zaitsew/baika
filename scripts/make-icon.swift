// Baika's app icon: a glowing amber orb with a voice waveform and two rings, the storyteller
// mid-sentence, on a deep ink field. Drawn at exactly 1024 x 1024 px.
//
//   swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset/icon-1024.png
//
// No alpha channel: App Store Connect refuses an icon that has one.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)
let center = CGPoint(x: s * 0.5, y: s * 0.5)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Field: ink, a little lighter toward the top.
let field = CGGradient(colorsSpace: space, colors: [rgb(0x2A211C), rgb(0x100D0B)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(field, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// Warm glow behind the orb.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xF2A33A, 0.38), rgb(0xF2A33A, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.52, options: [])

// Rings: the voice travelling outward.
for (index, radius) in [s * 0.40, s * 0.30].enumerated() {
    ctx.setStrokeColor(rgb(0xF2A33A, index == 0 ? 0.28 : 0.5))
    ctx.setLineWidth(s * 0.012)
    ctx.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

// Orb.
let orbRadius = s * 0.215
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - orbRadius, y: center.y - orbRadius, width: orbRadius * 2, height: orbRadius * 2))
ctx.clip()
let orb = CGGradient(colorsSpace: space, colors: [rgb(0xFFC166), rgb(0xC97A12)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    orb, startCenter: CGPoint(x: center.x - orbRadius * 0.3, y: center.y + orbRadius * 0.35), startRadius: 0,
    endCenter: center, endRadius: orbRadius * 1.25, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// Waveform: five rounded bars across the orb.
let heights: [CGFloat] = [0.10, 0.20, 0.30, 0.20, 0.10]
let barWidth = s * 0.034
let gap = s * 0.026
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
ctx.setFillColor(rgb(0x14110F))
for (index, factor) in heights.enumerated() {
    let height = s * factor
    let x = center.x - totalWidth / 2 + CGFloat(index) * (barWidth + gap)
    let rect = CGRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
}

guard let image = ctx.makeImage() else { fatalError("could not render the icon") }
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let url = URL(fileURLWithPath: path)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not open \(path)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(path)") }
print("wrote \(path)")
