import AppKit

/// A small see-through window that carries the critter along the menu bar.
/// It sits above the menu bar and its icons but below open menus and banners,
/// and it covers only the sprite, so the rest of the bar keeps working.
@MainActor
final class Walker {
    var onClick: () -> Void = {}

    private let panel: NSPanel
    private let sprite = CALayer()

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

        let view = ClickView()
        view.wantsLayer = true
        view.onClick = { [weak self] in self?.onClick() }
        panel.contentView = view
        sprite.magnificationFilter = .nearest
        view.layer?.addSublayer(sprite)
    }

    var isShown: Bool { panel.isVisible }

    /// Shows `image` in `frame`, given in screen points.
    func show(_ image: CGImage?, frame: NSRect, scale: CGFloat) {
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = NSRect(origin: .zero, size: frame.size)
        sprite.contentsScale = scale
        sprite.contents = image
        CATransaction.commit()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }
}

private final class ClickView: NSView {
    var onClick: () -> Void = {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
}
