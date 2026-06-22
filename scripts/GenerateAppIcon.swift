#!/usr/bin/env swift
import AppKit
import CoreGraphics

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "EventCountdown/Assets.xcassets/AppIcon.appiconset"

let sizes: [(name: String, side: Int)] = [
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

func drawIcon(side: Int) -> NSImage {
    let pixels = side
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return NSImage(size: NSSize(width: pixels, height: pixels))
    }

    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let sideCGFloat = CGFloat(pixels)
    let rect = NSRect(x: 0, y: 0, width: sideCGFloat, height: sideCGFloat)
    NSColor.clear.setFill()
    rect.fill()

    let pad = sideCGFloat * 0.08
    let calendarRect = rect.insetBy(dx: pad, dy: pad)
    let corner = sideCGFloat * 0.18

    // Calendar body
    let bodyPath = NSBezierPath(roundedRect: calendarRect, xRadius: corner, yRadius: corner)
    NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1).setFill()
    bodyPath.fill()

    let headerHeight = calendarRect.height * 0.28
    let headerRect = NSRect(
        x: calendarRect.minX,
        y: calendarRect.maxY - headerHeight,
        width: calendarRect.width,
        height: headerHeight
    )
    let headerPath = NSBezierPath(
        roundedRect: headerRect,
        xRadius: corner,
        yRadius: corner
    )
    NSColor(calibratedRed: 0.91, green: 0.23, blue: 0.23, alpha: 1).setFill()
    headerPath.fill()

    // Header bottom cover for square bottom edge
    let cover = NSRect(x: calendarRect.minX, y: headerRect.minY, width: calendarRect.width, height: corner)
    NSColor(calibratedRed: 0.91, green: 0.23, blue: 0.23, alpha: 1).setFill()
    cover.fill()

    // Calendar rings
    let ringY = headerRect.minY + headerHeight * 0.15
    let ringW = calendarRect.width * 0.07
    let ringH = headerHeight * 0.55
    for xFactor: CGFloat in [0.28, 0.72] {
        let ring = NSRect(
            x: calendarRect.minX + calendarRect.width * xFactor - ringW / 2,
            y: ringY,
            width: ringW,
            height: ringH
        )
        let ringPath = NSBezierPath(roundedRect: ring, xRadius: ringW / 2, yRadius: ringW / 4)
        NSColor.white.withAlphaComponent(0.95).setFill()
        ringPath.fill()
    }

    // Inner clock circle
    let clockDiameter = calendarRect.width * 0.52
    let clockRect = NSRect(
        x: calendarRect.midX - clockDiameter / 2,
        y: calendarRect.minY + calendarRect.height * 0.18,
        width: clockDiameter,
        height: clockDiameter
    )
    let clockPath = NSBezierPath(ovalIn: clockRect)
    NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.95, alpha: 1).setFill()
    clockPath.fill()

    NSColor.white.withAlphaComponent(0.25).setStroke()
    clockPath.lineWidth = max(1, sideCGFloat * 0.02)
    clockPath.stroke()

    // Clock hands (countdown pose ~ 10:50)
    let center = NSPoint(x: clockRect.midX, y: clockRect.midY)
    func hand(to angle: CGFloat, length: CGFloat, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        let end = NSPoint(
            x: center.x + cos(angle) * length,
            y: center.y + sin(angle) * length
        )
        path.move(to: center)
        path.line(to: end)
        color.setStroke()
        path.stroke()
    }

    let hourAngle = (-CGFloat.pi / 2) + (CGFloat.pi / 6) * 10
    let minuteAngle = (-CGFloat.pi / 2) + (CGFloat.pi / 30) * 50
    hand(to: hourAngle, length: clockDiameter * 0.22, width: max(1.2, sideCGFloat * 0.05), color: .white)
    hand(to: minuteAngle, length: clockDiameter * 0.34, width: max(1, sideCGFloat * 0.035), color: NSColor.white.withAlphaComponent(0.92))

    let pivot = NSBezierPath(ovalIn: NSRect(
        x: center.x - clockDiameter * 0.06,
        y: center.y - clockDiameter * 0.06,
        width: clockDiameter * 0.12,
        height: clockDiameter * 0.12
    ))
    NSColor.white.setFill()
    pivot.fill()

    // Countdown arc (remaining time wedge)
    let arcPath = NSBezierPath()
    arcPath.appendArc(
        withCenter: center,
        radius: clockDiameter * 0.42,
        startAngle: 110,
        endAngle: 20,
        clockwise: true
    )
    NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.2, alpha: 1).setStroke()
    arcPath.lineWidth = max(1.5, sideCGFloat * 0.05)
    arcPath.lineCapStyle = .round
    arcPath.stroke()

    // Outer subtle border
    NSColor(calibratedWhite: 0.55, alpha: 0.35).setStroke()
    bodyPath.lineWidth = max(0.5, sideCGFloat * 0.01)
    bodyPath.stroke()

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.addRepresentation(rep)
    return image
}

let fm = FileManager.default
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for entry in sizes {
    let image = drawIcon(side: entry.side)
    guard let rep = image.representations.first as? NSBitmapImageRep,
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        exit(1)
    }
    let path = "\(outputDir)/\(entry.name)"
    try png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

print("Done.")
