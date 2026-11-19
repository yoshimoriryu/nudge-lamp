import AppKit

/// A see-through strip over the menu bar that carries the walking critter.
///
/// The strip stays put and only the sprite layer moves inside it, which costs far less than
/// moving a window every frame. It sits above the menu bar and its icons but below open menus
/// and banners. Clicks pass straight through, except while the pointer is over the critter.
@MainActor
final class Walker {
    var onClick: () -> Void = {}

    private let panel: NSPanel
    private let view = ClickView()
    private let sprite = CALayer()
    private var shown: CGImage?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Every desktop, but not over full-screen apps, and never in the window cycle.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true

        view.wantsLayer = true
        view.onClick = { [weak self] point in
            guard let self, self.sprite.frame.contains(point) else { return }
            self.onClick()
        }
        panel.contentView = view
        sprite.magnificationFilter = .nearest
        view.layer?.addSublayer(sprite)
    }

    /// Shows `image` at `frame` inside the strip `track`, both in screen points.
    /// Only what changed goes to the window server.
    func show(_ image: CGImage?, frame: NSRect, track: NSRect) {
        if panel.frame != track { panel.setFrame(track, display: false) }
        let local = frame.offsetBy(dx: -track.minX, dy: -track.minY)
        if sprite.frame != local || image !== shown {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.frame = local
            if image !== shown { sprite.contents = image }
            CATransaction.commit()
            shown = image
        }
        // Catch clicks only while the pointer is over the critter.
        let over = frame.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}

private final class ClickView: NSView {
    var onClick: (NSPoint) -> Void = { _ in }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        onClick(convert(event.locationInWindow, from: nil))
    }
}
