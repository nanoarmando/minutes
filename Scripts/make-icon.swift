// Renders Resources/AppIcon.icns: the waveform mark from the approved UI mock, white on a #1D1D1F tile.
// Run from the repository root after changing the design: swift Scripts/make-icon.swift
import AppKit

let iconset = URL(fileURLWithPath: ".build/AppIcon.iconset", isDirectory: true)
let output = URL(fileURLWithPath: "Resources/AppIcon.icns")

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let unit = size / 1024

    // macOS icon grid: an 824 pt tile centered in the 1024 pt canvas, with a soft drop shadow.
    let tile = CGRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * unit), blur: 28 * unit,
                      color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.3))
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Five rounded bars, as in the mock's 24-unit SVG (x 4…20, stroke 2), scaled to 54 % of the tile.
    let scale = 824 * 0.54 / 24 * unit
    let origin = CGPoint(x: tile.midX - 12 * scale, y: tile.midY - 12 * scale)
    let bars: [(x: CGFloat, from: CGFloat, to: CGFloat)] = [(4, 10, 14), (8, 7, 17), (12, 4, 20), (16, 8, 16), (20, 11, 13)]
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(2 * scale)
    context.setLineCap(.round)
    for bar in bars {
        context.move(to: CGPoint(x: origin.x + bar.x * scale, y: origin.y + bar.from * scale))
        context.addLine(to: CGPoint(x: origin.x + bar.x * scale, y: origin.y + bar.to * scale))
    }
    context.strokePath()

    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
