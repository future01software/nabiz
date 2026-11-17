// Draws the app icon and writes Resources/AppIcon.icns.
// Run: swift Tools/make-icon.swift   (from the project folder)
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // Squircle body with a soft drop shadow (macOS icon grid: 824pt body).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(starting: hex(0x2A2E38), ending: hex(0x111318))!.draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Gentle teal glow from the top.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [hex(0x2FB5A8, 0.30), hex(0x2FB5A8, 0)])!
        .draw(fromCenter: NSPoint(x: 512, y: 900), radius: 0, toCenter: NSPoint(x: 512, y: 900), radius: 620, options: [])
    NSGraphicsContext.restoreGraphicsState()

    // Thin inner rim.
    hex(0xFFFFFF, 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183)
    rim.lineWidth = 6
    rim.stroke()

    // 270° dial: faint track, then four colored segments.
    let center = NSPoint(x: 512, y: 488)
    let radius: CGFloat = 262
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 225, endAngle: -45, clockwise: true)
    track.lineWidth = 60
    track.lineCapStyle = .round
    hex(0xFFFFFF, 0.08).setStroke()
    track.stroke()

    let colors: [UInt32] = [0xFF7A59, 0xE0B04B, 0x2FB5A8, 0x8B6CF6]
    var angle: CGFloat = 225
    let segment: CGFloat = 51, gap: CGFloat = 9
    for c in colors {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle - segment, clockwise: true)
        arc.lineWidth = 60
        arc.lineCapStyle = .round
        hex(c).setStroke()
        arc.stroke()
        angle -= segment + gap
    }

    // Tick marks inside the dial.
    for i in 0...10 {
        let a = (225 - CGFloat(i) * 27) * .pi / 180
        let r1: CGFloat = i % 5 == 0 ? 186 : 200, r2: CGFloat = 220
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        tick.line(to: NSPoint(x: center.x + cos(a) * r2, y: center.y + sin(a) * r2))
        tick.lineWidth = i % 5 == 0 ? 10 : 7
        tick.lineCapStyle = .round
        hex(0xFFFFFF, 0.28).setStroke()
        tick.stroke()
    }

    // Pulse line through the middle.
    let pts: [(CGFloat, CGFloat)] = [(318, 470), (420, 470), (460, 560), (510, 360), (556, 520), (590, 470), (706, 470)]
    let pulse = NSBezierPath()
    pulse.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
    for p in pts.dropFirst() { pulse.line(to: NSPoint(x: p.0, y: p.1)) }
    pulse.lineWidth = 36
    pulse.lineCapStyle = .round
    pulse.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = hex(0x2FB5A8, 0.8)
    glow.shadowBlurRadius = 30
    glow.set()
    NSColor.white.setStroke()
    pulse.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Small dot under the dial opening.
    hex(0xFFFFFF, 0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: 490, y: 196, width: 44, height: 44)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = drawIcon(size: px).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
try! drawIcon(size: 1024).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
