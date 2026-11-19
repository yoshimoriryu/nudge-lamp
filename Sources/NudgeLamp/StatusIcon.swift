import NudgeLampCore
import AppKit

@MainActor
enum StatusIcon {
    /// - Parameter frame: increments once per second; animates the working icon.
    static func image(for state: LampState, frame: Int = 0, pointSize: CGFloat = 15) -> NSImage {
        let (symbol, color) = style(for: state, frame: frame)
        let size = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: label(for: state)) ?? NSImage()
        guard let color else {
            let image = base.withSymbolConfiguration(size) ?? base
            image.isTemplate = true
            return image
        }
        let image = base.withSymbolConfiguration(size.applying(.init(paletteColors: [color]))) ?? base
        image.isTemplate = false
        return image
    }

    static func label(for state: LampState) -> String {
        switch state {
        case .blocked: "Waiting for you"
        case .finished: "Finished, your turn"
        case .working: "Working"
        case .idle: "Idle"
        }
    }

    private static func style(for state: LampState, frame: Int) -> (String, NSColor?) {
        switch state {
        case .blocked: ("exclamationmark.circle.fill", .systemRed)
        case .finished: ("checkmark.circle.fill", .systemOrange)
        case .working: (frame % 2 == 0 ? "circle.lefthalf.filled" : "circle.righthalf.filled", .systemGreen)
        case .idle: ("circle", nil)
        }
    }
}
