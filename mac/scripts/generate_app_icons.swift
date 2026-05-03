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
    c(0x0B1220).setFill()
    roundedRect(canvas.insetBy(dx: 28 * scale, dy: 28 * scale), radius: 220 * scale).fill()

    let glow = NSGradient(colors: [c(0x0EA5E9, 0.75), c(0x2563EB, 0.18), c(0x0B1220, 0.0)])!
    glow.draw(in: roundedRect(canvas.insetBy(dx: 60 * scale, dy: 60 * scale), radius: 190 * scale), angle: 45)

    let left = CGRect(x: 162 * scale, y: 548 * scale, width: 284 * scale, height: 184 * scale)
    let right = CGRect(x: 578 * scale, y: 294 * scale, width: 284 * scale, height: 184 * scale)
    for rect in [left, right] {
        c(0x0F2747, 0.96).setFill()
        roundedRect(rect, radius: 34 * scale).fill()
        c(0x38BDF8, 0.92).setStroke()
        let stroke = roundedRect(rect, radius: 34 * scale)
        stroke.lineWidth = 16 * scale
        stroke.stroke()

        let stand = NSBezierPath()
        stand.move(to: CGPoint(x: rect.midX, y: rect.minY))
        stand.line(to: CGPoint(x: rect.midX, y: rect.minY - 42 * scale))
        stand.move(to: CGPoint(x: rect.midX - 60 * scale, y: rect.minY - 42 * scale))
        stand.line(to: CGPoint(x: rect.midX + 60 * scale, y: rect.minY - 42 * scale))
        c(0x38BDF8, 0.78).setStroke()
        stand.lineWidth = 18 * scale
        stand.lineCapStyle = .round
        stand.stroke()
    }

    let bridge = NSBezierPath()
    bridge.move(to: CGPoint(x: left.maxX + 28 * scale, y: left.midY - 20 * scale))
    bridge.curve(
        to: CGPoint(x: right.minX - 28 * scale, y: right.midY + 22 * scale),
        controlPoint1: CGPoint(x: 500 * scale, y: 640 * scale),
        controlPoint2: CGPoint(x: 524 * scale, y: 410 * scale)
    )
    c(0x22C55E, 0.90).setStroke()
    bridge.lineWidth = 26 * scale
    bridge.lineCapStyle = .round
    bridge.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: CGPoint(x: 430 * scale, y: 426 * scale))
    cursor.line(to: CGPoint(x: 430 * scale, y: 204 * scale))
    cursor.line(to: CGPoint(x: 585 * scale, y: 350 * scale))
    cursor.line(to: CGPoint(x: 505 * scale, y: 364 * scale))
    cursor.line(to: CGPoint(x: 548 * scale, y: 462 * scale))
    cursor.line(to: CGPoint(x: 494 * scale, y: 486 * scale))
    cursor.line(to: CGPoint(x: 454 * scale, y: 390 * scale))
    cursor.close()
    c(0xF8FAFC).setFill()
    cursor.fill()
    c(0x020617, 0.38).setStroke()
    cursor.lineWidth = 12 * scale
    cursor.stroke()

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
