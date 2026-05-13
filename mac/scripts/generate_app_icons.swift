#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let macResourceDir = root.appendingPathComponent("mac/App/Resources", isDirectory: true)
let windowsAssetDir = root.appendingPathComponent("windows/App/Assets", isDirectory: true)
let iconsetDir = root.appendingPathComponent("mac/App/Resources/BarelyRealIcon.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: macResourceDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: windowsAssetDir, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }

    let canvas = CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size))
    let base = roundedRect(canvas.insetBy(dx: 86 * scale, dy: 86 * scale), radius: 180 * scale)

    let shadow = NSShadow()
    shadow.shadowColor = c(0x2563EB, 0.42)
    shadow.shadowBlurRadius = 72 * scale
    shadow.shadowOffset = CGSize(width: 0, height: -18 * scale)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    c(0x2563EB, 0.70).setFill()
    base.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    base.addClip()
    NSGradient(colors: [c(0x6D5DFB), c(0x4F46E5), c(0x2563EB)])!
        .draw(in: base.bounds, angle: -42)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    base.addClip()
    NSGradient(colors: [c(0xA5B4FC, 0.50), c(0xFFFFFF, 0.05), c(0x111827, 0.0)])!
        .draw(in: CGRect(x: 110 * scale, y: 600 * scale, width: 560 * scale, height: 360 * scale), angle: -28)
    NSGraphicsContext.restoreGraphicsState()

    let highlight = roundedRect(base.bounds.insetBy(dx: 26 * scale, dy: 26 * scale), radius: 148 * scale)
    c(0xFFFFFF, 0.14).setStroke()
    highlight.lineWidth = 10 * scale
    highlight.stroke()

    func drawMonitor(_ rect: CGRect, radius: CGFloat, strokeWidth: CGFloat, alpha: CGFloat) {
        let screen = roundedRect(rect, radius: radius * scale)

        NSGraphicsContext.saveGraphicsState()
        let monitorShadow = NSShadow()
        monitorShadow.shadowColor = c(0x1E1B4B, 0.28)
        monitorShadow.shadowBlurRadius = 18 * scale
        monitorShadow.shadowOffset = CGSize(width: 0, height: -8 * scale)
        monitorShadow.set()
        c(0xFFFFFF, 0.10 * alpha).setFill()
        screen.fill()
        NSGraphicsContext.restoreGraphicsState()

        c(0xFFFFFF, 0.95 * alpha).setStroke()
        screen.lineWidth = strokeWidth * scale
        screen.stroke()

        let stand = NSBezierPath()
        stand.move(to: CGPoint(x: rect.midX, y: rect.minY - 4 * scale))
        stand.line(to: CGPoint(x: rect.midX, y: rect.minY - 58 * scale))
        stand.move(to: CGPoint(x: rect.midX - 72 * scale, y: rect.minY - 58 * scale))
        stand.line(to: CGPoint(x: rect.midX + 72 * scale, y: rect.minY - 58 * scale))
        stand.lineWidth = strokeWidth * 0.82 * scale
        stand.lineCapStyle = .round
        stand.lineJoinStyle = .round
        stand.stroke()
    }

    drawMonitor(
        CGRect(x: 484 * scale, y: 342 * scale, width: 322 * scale, height: 248 * scale),
        radius: 38,
        strokeWidth: 30,
        alpha: 0.78
    )
    drawMonitor(
        CGRect(x: 218 * scale, y: 432 * scale, width: 422 * scale, height: 304 * scale),
        radius: 44,
        strokeWidth: 34,
        alpha: 1
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconsetFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

var pngBySize: [Int: Data] = [:]
for (_, size) in iconsetFiles {
    pngBySize[size] = pngBySize[size] ?? drawIcon(size: size)
}

for (name, size) in iconsetFiles {
    try pngBySize[size]!.write(to: iconsetDir.appendingPathComponent(name))
}
try pngBySize[256]!.write(to: windowsAssetDir.appendingPathComponent("BarelyReal.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir.path, "-o", macResourceDir.appendingPathComponent("BarelyRealIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "BarelyRealIcon", code: Int(process.terminationStatus))
}

func appendLE16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
}

func appendLE32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 24) & 0xff))
}

let icoSizes = [16, 32, 48, 256]
pngBySize[48] = drawIcon(size: 48)
var ico = Data()
appendLE16(0, to: &ico)
appendLE16(1, to: &ico)
appendLE16(UInt16(icoSizes.count), to: &ico)
let headerSize = 6 + icoSizes.count * 16
var offset = headerSize
for size in icoSizes {
    let png = pngBySize[size]!
    ico.append(size == 256 ? 0 : UInt8(size))
    ico.append(size == 256 ? 0 : UInt8(size))
    ico.append(0)
    ico.append(0)
    appendLE16(1, to: &ico)
    appendLE16(32, to: &ico)
    appendLE32(UInt32(png.count), to: &ico)
    appendLE32(UInt32(offset), to: &ico)
    offset += png.count
}
for size in icoSizes {
    ico.append(pngBySize[size]!)
}
try ico.write(to: windowsAssetDir.appendingPathComponent("BarelyReal.ico"))

print("Generated BarelyRealIcon.icns and BarelyReal.ico")
