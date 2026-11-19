import NudgeLampCore
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the critter animations to files, for the README and for eyeballing new poses.
enum DocRenderer {
    static let scale: CGFloat = 6
    static let background = NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)

    /// Writes one looping GIF per mood plus `sheet.png`, a grid of every variant.
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mood in CritterMood.allCases {
            let frames = CritterVariant.variants(for: mood).flatMap { variant in
                (0..<32).compactMap { frame(variant.pose(at: $0)) }
            }
            try writeGIF(frames, to: directory.appendingPathComponent("\(mood).gif"))
        }
        try writeSheet(to: directory.appendingPathComponent("sheet.png"))
        try writeSheet(to: directory.appendingPathComponent("sheet-tight.png"), lift: CritterLayout.tightLift)
        try writeShowcase(to: directory.appendingPathComponent("showcase.gif"))
    }

    /// All four moods side by side with captions, cycling through every variant.
    private static func writeShowcase(to url: URL) throws {
        let moods: [(CritterMood, String)] = [
            (.blocked, "Needs you"), (.finished, "Finished"), (.working, "Working"), (.idle, "Idle"),
        ]
        let big: CGFloat = 8
        let cellW = Int(CGFloat(CritterRenderer.columns) * big) + 24
        let spriteH = Int(CGFloat(CritterRenderer.rows) * big)
        let captionH = 40
        let width = cellW * moods.count, height = spriteH + captionH + 12
        let caption: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(white: 0.85, alpha: 1),
        ]
        var frames: [CGImage] = []
        for t in 0..<(32 * 3) {
            let image = bitmap(width: width, height: height) {
                background.setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
                for (i, (mood, label)) in moods.enumerated() {
                    let variants = CritterVariant.variants(for: mood)
                    let pose = variants[t / 32].pose(at: t % 32)
                    let x = i * cellW + 12
                    CritterRenderer.image(pose, scale: big)
                        .draw(in: NSRect(x: x, y: captionH, width: cellW - 24, height: spriteH))
                    let text = NSAttributedString(string: label, attributes: caption)
                    let size = text.size()
                    text.draw(at: NSPoint(x: CGFloat(i * cellW) + (CGFloat(cellW) - size.width) / 2, y: 10))
                }
            }
            if let image { frames.append(image) }
        }
        try writeGIF(frames, to: url)
    }

    private static var cellSize: (Int, Int) {
        (Int(CGFloat(CritterRenderer.columns) * scale), Int(CGFloat(CritterRenderer.rows) * scale))
    }

    private static func frame(_ pose: CritterPose) -> CGImage? {
        let (w, h) = cellSize
        return bitmap(width: w, height: h) {
            background.setFill()
            NSRect(x: 0, y: 0, width: w, height: h).fill()
            CritterRenderer.image(pose, scale: scale).draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// - Parameter lift: jump headroom; `tightLift` shows the Extra Large layout on a 38 pt bar.
    private static func writeSheet(to url: URL, lift: Int = CritterLayout.fullLift) throws {
        let w = cellSize.0
        let h = Int(CGFloat(CritterLayout.bodyRows + lift) * scale)
        let variants = CritterVariant.allCases
        let samples = Array(stride(from: 0, to: 32, by: 3))
        let image = bitmap(width: w * samples.count, height: h * variants.count) {
            background.setFill()
            NSRect(x: 0, y: 0, width: w * samples.count, height: h * variants.count).fill()
            for (row, variant) in variants.enumerated() {
                for (column, t) in samples.enumerated() {
                    // Bitmap contexts are not flipped, so row 0 goes at the top.
                    let y = (variants.count - 1 - row) * h
                    CritterRenderer.image(variant.pose(at: t), scale: scale, lift: lift)
                        .draw(in: NSRect(x: column * w, y: y, width: w, height: h))
                }
            }
        }
        guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }

    private static func bitmap(width: Int, height: Int, _ draw: () -> Void) -> CGImage? {
        CritterRenderer.bitmap(width: width, height: height, appearance: NSAppearance(named: .darkAqua), draw)
    }

    private static func writeGIF(_ frames: [CGImage], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        let loop = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loop as CFDictionary)
        let delay = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / CritterAnimator.fps]]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, delay as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
