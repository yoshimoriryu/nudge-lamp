import AppKit
import NudgeLampCore

/// Draws a `CritterPose` as pixel art on a grid of `columns` by `rows` sprite pixels.
/// The critter is a light bulb with a face, thin metal arms and a screw base for a body.
enum CritterRenderer {
    static let columns = 23
    /// Canvas height with full jump headroom. `lift` trims it when the menu bar is short.
    static let rows = CritterLayout.bodyRows + CritterLayout.fullLift

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static let ink = rgb(0x1F2328)
    private static let metalLight = rgb(0xC5CAD3)
    private static let metalDark = rgb(0x8C929C)
    private static let contact = rgb(0x5B6069)
    private static let foot = rgb(0x4A4F57)
    private static let shine = NSColor(white: 1, alpha: 0.85)
    private static let red = NSColor.systemRed
    private static let yellow = NSColor.systemYellow

    /// Glass fill and outline for each bulb color.
    private static func glass(_ bulb: CritterPose.Bulb) -> (fill: NSColor, rim: NSColor) {
        switch bulb {
        case .off: (rgb(0xC9CED6), rgb(0x8E949E))
        case .green: (rgb(0x4ADE80), rgb(0x15803D))
        case .mint: (rgb(0xA7F3C4), rgb(0x15803D))
        case .red: (rgb(0xFF5A5A), rgb(0xB91C1C))
        case .white: (rgb(0xFFB3AD), rgb(0xB91C1C))
        case .amber: (rgb(0xFCD34D), rgb(0xB45309))
        }
    }

    static func image(_ pose: CritterPose, scale: CGFloat = 1, lift: Int = CritterLayout.fullLift) -> NSImage {
        let rows = CritterLayout.bodyRows + lift
        let size = NSSize(width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(pose, scale: scale, lift: lift)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Rasterizes a pose for a CALayer. `appearance` resolves the label colors of the badges.
    static func cgImage(_ pose: CritterPose, pixelScale: CGFloat, lift: Int, appearance: NSAppearance) -> CGImage? {
        let width = Int(CGFloat(columns) * pixelScale)
        let height = Int(CGFloat(CritterLayout.bodyRows + lift) * pixelScale)
        return bitmap(width: width, height: height, appearance: appearance) {
            image(pose, scale: pixelScale, lift: lift).draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func bitmap(width: Int, height: Int, appearance: NSAppearance?, _ draw: () -> Void) -> CGImage? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .none
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    /// Draws into the current graphics context, which must be flipped (y grows downward).
    static func draw(_ pose: CritterPose, scale: CGFloat, lift: Int = CritterLayout.fullLift) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        if pose.dimmed { context?.setAlpha(0.75) }

        func px(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: NSColor) {
            color.setFill()
            NSBezierPath(rect: NSRect(
                x: CGFloat(x) * scale, y: CGFloat(y) * scale,
                width: CGFloat(w) * scale, height: CGFloat(h) * scale
            )).fill()
        }

        // Sprite origin: the glass spans columns ox...ox+9 and rows oy...oy+8,
        // the screw base rows oy+9...oy+12, and the feet row oy+13.
        let ox = 4 + pose.dx
        // Jumps higher than the headroom are clipped to it, so tight layouts jump less.
        let oy = lift + max(pose.dy, -lift)
        let (fill, rim) = glass(pose.bulb)

        // Glass: draw the rim shape, then fill it one pixel in.
        px(ox + 3, oy, 4, 1, rim)
        px(ox + 1, oy + 1, 8, 1, rim)
        px(ox, oy + 2, 10, 5, rim)
        px(ox + 1, oy + 7, 8, 1, rim)
        px(ox + 2, oy + 8, 6, 1, rim)
        px(ox + 3, oy + 1, 4, 1, fill)
        px(ox + 1, oy + 2, 8, 5, fill)
        px(ox + 2, oy + 7, 6, 1, fill)
        px(ox + 3, oy + 8, 4, 1, fill)
        px(ox + 2, oy + 2, 1, 2, shine)

        // Screw base and contact
        px(ox + 2, oy + 9, 6, 1, metalLight)
        px(ox + 2, oy + 10, 6, 1, metalDark)
        px(ox + 2, oy + 11, 6, 1, metalLight)
        px(ox + 3, oy + 12, 4, 1, contact)

        // Feet sit either side of the contact and lift one row when stepping
        px(ox + 1, oy + (pose.leftFootUp ? 12 : 13), 2, 1, foot)
        px(ox + 7, oy + (pose.rightFootUp ? 12 : 13), 2, 1, foot)

        // Thin metal arms
        func arm(_ x: Int, _ arm: CritterPose.Arm) {
            switch arm {
            case .side: px(x, oy + 4, 1, 2, metalDark)
            case .down: px(x, oy + 6, 1, 2, metalDark)
            case .forward: px(x, oy + 7, 1, 2, metalDark)
            case .up: px(x, oy + 1, 1, 3, metalDark)
            }
        }
        arm(ox - 1, pose.leftArm)
        arm(ox + 10, pose.rightArm)

        // Eyes
        let lx = ox + 2, rx = ox + 6, ey = oy + 4
        switch pose.eyes {
        case .open(let dx, let dy):
            px(lx + dx, ey + dy, 2, 2, ink)
            px(rx + dx, ey + dy, 2, 2, ink)
        case .closed:
            px(lx, ey + 1, 2, 1, ink)
            px(rx, ey + 1, 2, 1, ink)
        case .happy:
            for x in [lx - 1, rx] {
                px(x, ey + 1, 1, 1, ink)
                px(x + 1, ey, 1, 1, ink)
                px(x + 2, ey + 1, 1, 1, ink)
            }
        case .wide:
            px(lx, ey - 1, 2, 3, ink)
            px(rx, ey - 1, 2, 3, ink)
        }
        if pose.mouth {
            px(ox + 4, oy + 7, 2, 1, ink)
        }

        // Badge in the top-right corner, fixed so it stays readable while the body moves.
        // Badge rows assume full headroom; shift them up when the canvas is shorter.
        let by = lift - CritterLayout.fullLift
        func bx(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: NSColor) {
            px(x, max(0, y + by), w, h, color)
        }
        switch pose.badge {
        case .exclamation:
            // Keep the one-row gap above the dot; the bar gets shorter on a tight canvas.
            let barTop = max(0, 1 + by), dotTop = 8 + by
            px(19, barTop, 2, dotTop - 1 - barTop, red)
            px(19, dotTop, 2, 2, red)
        case .sparkle(let big):
            bx(19, 4, 3, 1, yellow)
            bx(20, 3, 1, 3, yellow)
            if big {
                bx(18, 4, 5, 1, yellow)
                bx(20, 2, 1, 5, yellow)
            }
        case .dots(let count):
            for i in 0..<max(0, min(3, count)) {
                bx(16 + i * 2, 2, 1, 1, .labelColor)
            }
        case .zee(let step):
            let x = 16 + step, y = 8 - step * 3
            let color = NSColor.secondaryLabelColor
            bx(x, y, 4, 1, color)
            bx(x + 2, y + 1, 1, 1, color)
            bx(x + 1, y + 2, 1, 1, color)
            bx(x, y + 3, 4, 1, color)
        case nil:
            break
        }
    }
}
