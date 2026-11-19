import AgentLampCore
import AppKit

/// Draws a `CritterPose` as pixel art on a grid of `columns` by `rows` sprite pixels.
enum CritterRenderer {
    static let columns = 23
    static let rows = 17

    private static let body = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)    // #D97757
    private static let shade = NSColor(srgbRed: 0.714, green: 0.373, blue: 0.259, alpha: 1)   // #B65F42
    private static let foot = NSColor(srgbRed: 0.600, green: 0.300, blue: 0.200, alpha: 1)    // #994D33
    private static let ink = NSColor(srgbRed: 0.145, green: 0.098, blue: 0.078, alpha: 1)     // #251914
    private static let red = NSColor.systemRed
    private static let yellow = NSColor.systemYellow

    static func image(_ pose: CritterPose, scale: CGFloat = 1) -> NSImage {
        let size = NSSize(width: CGFloat(columns) * scale, height: CGFloat(rows) * scale)
        let image = NSImage(size: size, flipped: true) { _ in
            draw(pose, scale: scale)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Rasterizes a pose for a CALayer. `appearance` resolves the label colors of the badges.
    static func cgImage(_ pose: CritterPose, pixelScale: CGFloat, appearance: NSAppearance) -> CGImage? {
        let width = Int(CGFloat(columns) * pixelScale)
        let height = Int(CGFloat(rows) * pixelScale)
        return bitmap(width: width, height: height, appearance: appearance) {
            image(pose, scale: pixelScale).draw(in: NSRect(x: 0, y: 0, width: width, height: height))
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
    static func draw(_ pose: CritterPose, scale: CGFloat) {
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        if pose.dimmed { context?.setAlpha(0.7) }

        func px(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1, _ color: NSColor) {
            color.setFill()
            NSBezierPath(rect: NSRect(
                x: CGFloat(x) * scale, y: CGFloat(y) * scale,
                width: CGFloat(w) * scale, height: CGFloat(h) * scale
            )).fill()
        }

        // Sprite origin: body spans columns ox...ox+11 and rows oy+3...oy+10.
        let ox = 4 + pose.dx
        let oy = 4 + pose.dy

        // Antenna
        let tipColor: NSColor = switch pose.tip {
        case .dim: shade
        case .glow: NSColor(srgbRed: 0.941, green: 0.635, blue: 0.498, alpha: 1)
        case .bright: NSColor(srgbRed: 1.0, green: 0.890, blue: 0.827, alpha: 1)
        case .red: red
        case .yellow: yellow
        }
        if pose.antennaDroop {
            px(ox + 5, oy + 2, 1, 1, shade)
            px(ox + 6, oy + 1, 2, 1, shade)
            px(ox + 8, oy + 1, 2, 2, tipColor)
        } else {
            let lean = max(-1, min(1, pose.antennaLean))
            px(ox + 5, oy + 2, 1, 1, shade)
            px(ox + 5 + lean, oy + 1, 1, 1, shade)
            px(ox + 5 + lean, oy - 1, 2, 2, tipColor)
        }

        // Body with clipped corners and a darker bottom row
        px(ox + 1, oy + 3, 10, 1, body)
        px(ox, oy + 4, 12, 6, body)
        px(ox + 1, oy + 10, 10, 1, shade)

        // Arms
        func arm(_ x: Int, _ arm: CritterPose.Arm) {
            switch arm {
            case .side: px(x, oy + 6, 1, 2, body)
            case .down: px(x, oy + 8, 1, 2, body)
            case .forward: px(x, oy + 9, 1, 2, body)
            case .up: px(x, oy + 2, 1, 3, body)
            }
        }
        arm(ox - 1, pose.leftArm)
        arm(ox + 12, pose.rightArm)

        // Feet
        px(ox + 2, oy + 11, 2, pose.leftFootUp ? 1 : 2, foot)
        px(ox + 8, oy + 11, 2, pose.rightFootUp ? 1 : 2, foot)

        // Eyes
        let lx = ox + 3, rx = ox + 7, ey = oy + 5
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
            px(ox + 5, oy + 8, 2, 1, ink)
        }

        // Badge in the top-right corner, fixed so it stays readable while the body moves
        switch pose.badge {
        case .exclamation:
            px(20, 1, 2, 6, red)
            px(20, 8, 2, 2, red)
        case .sparkle(let big):
            px(20, 4, 1, 1, yellow)
            px(19, 4, 3, 1, yellow)
            px(20, 3, 1, 3, yellow)
            if big {
                px(18, 4, 5, 1, yellow)
                px(20, 2, 1, 5, yellow)
            }
        case .dots(let count):
            for i in 0..<max(0, min(3, count)) {
                px(17 + i * 2, 3, 1, 1, .labelColor)
            }
        case .zee(let step):
            let x = 17 + step, y = 9 - step * 3
            let color = NSColor.secondaryLabelColor
            px(x, y, 4, 1, color)
            px(x + 2, y + 1, 1, 1, color)
            px(x + 1, y + 2, 1, 1, color)
            px(x, y + 3, 4, 1, color)
        case nil:
            break
        }
    }
}
