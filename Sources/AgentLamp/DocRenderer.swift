import AgentLampCore
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

    private static func writeSheet(to url: URL) throws {
        let (w, h) = cellSize
        let variants = CritterVariant.allCases
        let samples = Array(stride(from: 0, to: 32, by: 3))
        let image = bitmap(width: w * samples.count, height: h * variants.count) {
            background.setFill()
            NSRect(x: 0, y: 0, width: w * samples.count, height: h * variants.count).fill()
            for (row, variant) in variants.enumerated() {
                for (column, t) in samples.enumerated() {
                    // Bitmap contexts are not flipped, so row 0 goes at the top.
                    let y = (variants.count - 1 - row) * h
                    CritterRenderer.image(variant.pose(at: t), scale: scale)
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
