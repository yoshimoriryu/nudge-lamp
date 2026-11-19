import AgentLampCore
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notifier = Notifier()
    private var tracker = Tracker()
    private var views: [SessionView] = []
    private var timer: Timer?
    private var animationTimer: Timer?
    private var frame = 0
    private var menuIsOpen = false
    private var lampState: LampState = .idle
    private var animator = CritterAnimator()
    private var lastPose: CritterPose?
    /// The critter lives on its own layer. Swapping layer contents is cheap, while
    /// swapping `button.image` makes AppKit lay out and redraw the whole status item.
    private let critterLayer = CALayer()
    /// Each distinct pose is drawn once per appearance. All loops together use about a hundred small images.
    private var poseImages: [CritterPose: CGImage] = [:]
    private var poseImagesKey = ""
    /// Reserves room for the critter so the count still lays out to its right.
    private var critterPlaceholder = NSImage()
    /// Points per sprite pixel. Notched displays have a 38pt menu bar, so the critter grows there.
    /// 1.5pt is 3 device pixels on Retina, which keeps the pixel art sharp.
    private var pixelPoints: CGFloat {
        (statusItem.button?.bounds.height ?? 0) >= 30 ? 1.5 : 1
    }

    private let defaults = UserDefaults.standard
    private var soundOn: Bool {
        get { defaults.object(forKey: "sound") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sound") }
    }
    private var bannersOn: Bool {
        get { defaults.object(forKey: "banners") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "banners") }
    }
    private var characterOn: Bool {
        get { defaults.object(forKey: "character") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "character") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.wantsLayer = true
        critterLayer.magnificationFilter = .nearest
        statusItem.button?.layer?.addSublayer(critterLayer)

        notifier.onClick = { [weak self] pid in self?.reveal(pid: pid) }
        notifier.setUp()

        refresh()
        // Polling a handful of small files once a second costs less than watching them,
        // and it keeps working however Claude Code chooses to rewrite them.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let animationTimer = Timer(timeInterval: 1 / CritterAnimator.fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.animate() }
        }
        RunLoop.main.add(animationTimer, forMode: .common)
        self.animationTimer = animationTimer
    }

    /// Advances the critter one frame. Skips the redraw when the pose did not change.
    private func animate() {
        guard characterOn, let button = statusItem.button else { return }
        let pose = animator.next(mood: CritterMood(lampState))
        guard pose != lastPose else { return }
        lastPose = pose

        let scale = button.window?.backingScaleFactor ?? 2
        let appearance = button.effectiveAppearance
        let key = "\(appearance.name.rawValue)@\(scale)x\(pixelPoints)"
        if key != poseImagesKey {
            poseImages.removeAll()
            poseImagesKey = key
        }
        if poseImages[pose] == nil {
            poseImages[pose] = CritterRenderer.cgImage(pose, pixelScale: scale * pixelPoints, appearance: appearance)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        critterLayer.contentsScale = scale
        critterLayer.contents = poseImages[pose]
        CATransaction.commit()
    }

    // MARK: Polling

    private func refresh() {
        let records = SessionDirectory.load()
        let before = Set(views.filter(\.state.needsYou).map(\.record.sessionId))

        let update = tracker.update(records, now: Date(), focused: focusedSessionIds(records))
        views = update.views
        update.events.forEach(announce)

        let after = Set(views.filter(\.state.needsYou).map(\.record.sessionId))
        notifier.clear(sessionIds: Array(before.subtracting(after)))

        frame += 1
        updateButton()
        if menuIsOpen { rebuildMenu() }
    }

    private func focusedSessionIds(_ records: [SessionRecord]) -> Set<String> {
        guard let tty = ITerm.focusedTTY() else { return [] }
        return Set(records.filter { ProcessLookup.tty(of: $0.pid) == tty }.map(\.sessionId))
    }

    private func announce(_ event: LampEvent) {
        if bannersOn { notifier.post(event) }
        if soundOn { NSSound(named: event.state == .blocked ? "Funk" : "Glass")?.play() }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let summary = LampSummary(views)
        lampState = summary.state
        if characterOn {
            let size = NSSize(
                width: CGFloat(CritterRenderer.columns) * pixelPoints,
                height: CGFloat(CritterRenderer.rows) * pixelPoints
            )
            if critterPlaceholder.size != size { critterPlaceholder = NSImage(size: size) }
            if button.image !== critterPlaceholder { button.image = critterPlaceholder }
        } else {
            button.image = StatusIcon.image(for: summary.state, frame: frame)
        }
        let title = summary.needsYouCount > 0 ? " \(summary.needsYouCount)" : ""
        if button.title != title { button.title = title }
        button.toolTip = summary.needsYouCount > 0
            ? "\(summary.needsYouCount) Claude Code session(s) need you"
            : "Agent Lamp: \(StatusIcon.label(for: summary.state))"

        critterLayer.isHidden = !characterOn
        if characterOn, let cell = button.cell as? NSButtonCell {
            let frame = cell.imageRect(forBounds: button.bounds)
            if critterLayer.frame != frame {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                critterLayer.frame = frame
                CATransaction.commit()
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }
    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        if views.isEmpty {
            let empty = NSMenuItem(title: "No Claude Code sessions running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for view in views {
            let record = view.record
            let item = NSMenuItem(title: record.displayName, action: #selector(rowClicked(_:)), keyEquivalent: "")
            item.target = self
            item.image = StatusIcon.image(for: view.state, frame: frame, pointSize: 13)
            item.subtitle = "\(describe(view)), \(Self.duration(since: record.statusChangedAt, now: now))  ·  \(Self.shortPath(record.cwd))"
            item.representedObject = record.pid
            item.toolTip = "Click to open this session in iTerm2"
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if views.contains(where: { $0.state == .finished }) {
            menu.addItem(actionItem("Mark All as Seen", #selector(markAllSeen)))
        }
        menu.addItem(toggleItem("Play Sound", on: soundOn, #selector(toggleSound)))
        menu.addItem(toggleItem("Show Banners", on: bannersOn, #selector(toggleBanners)))
        menu.addItem(toggleItem("Animated Critter", on: characterOn, #selector(toggleCharacter)))
        menu.addItem(toggleItem("Open at Login", on: SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Agent Lamp", #selector(quit), key: "q"))
    }

    private func describe(_ view: SessionView) -> String {
        switch view.state {
        case .blocked:
            view.record.waitingFor.map { "Waiting for you: \($0)" } ?? "Waiting for you"
        case .finished:
            "Finished, your turn"
        case .working:
            view.record.status == "shell" ? "Running a shell command" : "Working"
        case .idle:
            "Idle"
        }
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, on: Bool, _ action: Selector) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = on ? .on : .off
        return item
    }

    // MARK: Actions

    @objc private func rowClicked(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        reveal(pid: pid)
    }

    private func reveal(pid: Int32) {
        if let record = views.first(where: { $0.record.pid == pid })?.record {
            tracker.acknowledge(sessionId: record.sessionId)
        }
        if let tty = ProcessLookup.tty(of: pid), ITerm.reveal(tty: tty) {
            // Revealed the exact tab.
        } else {
            ITerm.activate()
        }
        refresh()
    }

    @objc private func markAllSeen() {
        tracker.acknowledgeAll()
        refresh()
    }

    @objc private func toggleSound() { soundOn.toggle() }
    @objc private func toggleBanners() { bannersOn.toggle() }

    @objc private func toggleCharacter() {
        characterOn.toggle()
        lastPose = nil
        updateButton()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Agent Lamp: login item change failed: \(error.localizedDescription)")
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Formatting

    static func duration(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
