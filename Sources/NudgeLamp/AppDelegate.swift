import NudgeLampCore
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notifier = Notifier()
    private let source = SessionSource()
    private var tracker = Tracker()
    private var views: [SessionView] = []
    private var timer: Timer?
    private var animationTimer: Timer?
    private var frame = 0
    private var menuIsOpen = false
    private var openSubmenus = 0
    private var lampState: LampState = .idle
    private var animator = CritterAnimator()
    private var lastPose: CritterPose?
    /// The critter lives on its own layer. Swapping layer contents is cheap, while
    /// swapping `button.image` makes AppKit lay out and redraw the whole status item.
    private let critterLayer = CALayer()
    /// Each distinct pose is drawn once per appearance. All loops together use about a hundred small images.
    private var poseImages: [CritterPose: CGImage] = [:]
    private var poseImagesKey = ""
    private var notificationPermission: Permission = .notAsked
    /// Reserves room for the critter so the count still lays out to its right.
    private var critterPlaceholder = NSImage()
    private var critterSize: CritterSize {
        get { CritterSize(rawValue: defaults.string(forKey: "size") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "size") }
    }

    /// The chosen size, shrunk if needed to fit this menu bar. The status item button is only
    /// 22 pt tall, but its window spans the whole menu bar (38 pt on a notched display),
    /// and the critter may use all of it.
    private var critterLayout: CritterLayout {
        let barHeight = statusItem.button?.window?.frame.height ?? NSStatusBar.system.thickness
        return CritterLayout.fit(critterSize, barHeight: barHeight)
    }

    private let defaults = UserDefaults.standard
    /// Sound names for each event. "None" turns the sound off.
    private static let waitingSoundKey = "sound.waiting"
    private static let finishedSoundKey = "sound.finished"
    private static let soundDefaults = [waitingSoundKey: "Funk", finishedSoundKey: "Glass"]

    private func sound(_ key: String) -> String {
        defaults.string(forKey: key) ?? Self.soundDefaults[key] ?? "None"
    }

    /// Sounds NSSound can play by name: the macOS system sounds plus any the user added.
    private static let availableSounds: [String] = {
        let folders = [
            "/System/Library/Sounds",
            "/Library/Sounds",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds").path,
        ]
        let extensions: Set<String> = ["aiff", "aif", "wav", "mp3", "m4a", "caf"]
        var names = Set<String>()
        for folder in folders {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
                let url = URL(fileURLWithPath: file)
                if extensions.contains(url.pathExtension.lowercased()) {
                    names.insert(url.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return names.sorted()
    }()
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
        source.onUpdate = { [weak self] in self?.refresh() }
        notifier.setUp()
        refreshNotificationPermission()

        // install.sh passes this flag so a fresh install starts with the Mac.
        if CommandLine.arguments.contains("--enable-login-item") {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("Nudge Lamp: could not add login item: \(error.localizedDescription)")
            }
        }

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
        let layout = critterLayout
        let key = "\(appearance.name.rawValue)@\(scale)x\(layout.points)+\(layout.lift)"
        if key != poseImagesKey {
            poseImages.removeAll()
            poseImagesKey = key
        }
        if poseImages[pose] == nil {
            poseImages[pose] = CritterRenderer.cgImage(
                pose, pixelScale: scale * layout.points, lift: layout.lift, appearance: appearance
            )
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        critterLayer.contentsScale = scale
        critterLayer.contents = poseImages[pose]
        CATransaction.commit()
    }

    // MARK: Polling

    private func refresh() {
        source.poll()
        let records = source.records
        let before = Set(views.filter(\.state.needsYou).map(\.record.sessionId))

        // Asking iTerm2 for the focused tab is an Apple Event round trip. Only ask when the answer
        // can change something: a session needs you, or a session's status just changed.
        let previous = Dictionary(views.map { ($0.record.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        let focusMatters = records.contains { record in
            guard let old = previous[record.sessionId] else { return false }
            return old.state.needsYou || old.record.status != record.status
        }
        let focused = focusMatters ? focusedSessionIds(records) : []

        let update = tracker.update(records, now: Date(), focused: focused)
        views = update.views
        update.events.forEach(announce)

        let after = Set(views.filter(\.state.needsYou).map(\.record.sessionId))
        notifier.clear(sessionIds: Array(before.subtracting(after)))

        frame += 1
        updateButton()
        // Rebuilding while a submenu is open would close it.
        if menuIsOpen && openSubmenus == 0 { rebuildMenu() }
    }

    private func focusedSessionIds(_ records: [SessionRecord]) -> Set<String> {
        guard let tty = ScriptableTerminal.frontmost?.focusedTTY() else { return [] }
        return Set(records.filter { ProcessLookup.tty(of: $0.pid) == tty }.map(\.sessionId))
    }

    private func announce(_ event: LampEvent) {
        if bannersOn { notifier.post(event) }
        play(sound(event.state == .blocked ? Self.waitingSoundKey : Self.finishedSoundKey))
    }

    private func play(_ name: String) {
        guard name != "None" else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let summary = LampSummary(views)
        lampState = summary.state
        let layout = critterLayout
        let critterWidth = CGFloat(CritterRenderer.columns) * layout.points
        let critterHeight = CGFloat(layout.height)
        if characterOn {
            // The placeholder only reserves width. Keeping it no taller than the button stops
            // the cell from scaling it, which would also shrink the reserved width.
            let size = NSSize(width: critterWidth, height: min(critterHeight, button.bounds.height))
            if critterPlaceholder.size != size { critterPlaceholder = NSImage(size: size) }
            if button.image !== critterPlaceholder { button.image = critterPlaceholder }
        } else {
            button.image = StatusIcon.image(for: summary.state, frame: frame)
        }
        let title = summary.needsYouCount > 0 ? " \(summary.needsYouCount)" : ""
        if button.title != title { button.title = title }
        button.toolTip = summary.needsYouCount > 0
            ? "\(summary.needsYouCount) Claude Code session(s) need you"
            : "Nudge Lamp: \(StatusIcon.label(for: summary.state))"

        critterLayer.isHidden = !characterOn
        if characterOn, let cell = button.cell as? NSButtonCell {
            // Center the critter on the button; it may extend above and below it into the bar.
            let slot = cell.imageRect(forBounds: button.bounds)
            let frame = NSRect(
                x: slot.minX,
                y: ((button.bounds.height - critterHeight) / 2).rounded(),
                width: critterWidth,
                height: critterHeight
            )
            if critterLayer.frame != frame {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                critterLayer.frame = frame
                CATransaction.commit()
            }
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu { rebuildMenu() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else {
            openSubmenus += 1
            return
        }
        menuIsOpen = true
        refreshNotificationPermission()
    }

    private func refreshNotificationPermission() {
        Task {
            let permission = await Doctor.notifications()
            if permission != notificationPermission {
                notificationPermission = permission
                if menuIsOpen { rebuildMenu() }
            }
        }
    }

    /// Menu items that fix missing permissions. Empty once everything is allowed.
    private func setupItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        switch notificationPermission {
        case .allowed: break
        case .notAsked: items.append(actionItem("Allow Notifications…", #selector(askNotifications)))
        case .denied, .unavailable: items.append(actionItem("Turn On Notifications in Settings…", #selector(openNotificationSettings)))
        }
        // Only running terminals report a permission state; the rest show nothing.
        for terminal in ScriptableTerminal.allCases {
            switch Doctor.control(of: terminal) {
            case .notAsked:
                let item = actionItem("Allow \(terminal.name) Tab Switching…", #selector(askTerminalControl(_:)))
                item.representedObject = terminal.bundleID
                items.append(item)
            case .denied:
                items.append(actionItem("Allow \(terminal.name) Tab Switching in Settings…", #selector(openAutomationSettings)))
            default:
                break
            }
        }
        return items
    }
    func menuDidClose(_ menu: NSMenu) {
        if menu === self.menu {
            menuIsOpen = false
            openSubmenus = 0
        } else {
            openSubmenus = max(0, openSubmenus - 1)
        }
    }

    /// A submenu listing every available sound, with the current choice checked.
    private func soundMenu(_ title: String, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let current = sound(key)
        item.subtitle = current
        let submenu = NSMenu()
        submenu.delegate = self
        submenu.autoenablesItems = false
        for name in ["None"] + Self.availableSounds {
            let choice = NSMenuItem(title: name, action: #selector(chooseSound(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = [key, name]
            choice.state = name == current ? .on : .off
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let now = Date()

        if let problem = source.problem {
            let item = NSMenuItem(title: problem, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if views.isEmpty {
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
            item.toolTip = "Click to open this session in its terminal"
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let setup = setupItems()
        if !setup.isEmpty {
            let header = NSMenuItem(title: "Setup", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            setup.forEach(menu.addItem)
            menu.addItem(.separator())
        }
        if views.contains(where: { $0.state == .finished }) {
            menu.addItem(actionItem("Mark All as Seen", #selector(markAllSeen)))
        }
        menu.addItem(soundMenu("Sound When Waiting", key: Self.waitingSoundKey))
        menu.addItem(soundMenu("Sound When Finished", key: Self.finishedSoundKey))
        menu.addItem(toggleItem("Show Banners", on: bannersOn, #selector(toggleBanners)))
        menu.addItem(toggleItem("Animated Critter", on: characterOn, #selector(toggleCharacter)))
        menu.addItem(sizeMenu())
        menu.addItem(toggleItem("Open at Login", on: SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Nudge Lamp", #selector(quit), key: "q"))
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
        Terminals.reveal(pid: pid)
        refresh()
    }

    @objc private func markAllSeen() {
        tracker.acknowledgeAll()
        refresh()
    }

    @objc private func askNotifications() {
        notifier.setUp()
        refreshNotificationPermission()
    }

    @objc private func openNotificationSettings() {
        NSWorkspace.shared.open(Doctor.notificationSettingsURL)
    }

    @objc private func askTerminalControl(_ sender: NSMenuItem) {
        guard let terminal = ScriptableTerminal(bundleID: sender.representedObject as? String) else { return }
        // The consent prompt blocks the calling thread until answered, so keep it off the main thread.
        Task.detached { _ = Doctor.control(of: terminal, askIfNeeded: true) }
    }

    @objc private func openAutomationSettings() {
        NSWorkspace.shared.open(Doctor.automationSettingsURL)
    }

    /// Saves the picked sound and plays it once as a preview.
    @objc private func chooseSound(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        defaults.set(pair[1], forKey: pair[0])
        play(pair[1])
    }
    @objc private func toggleBanners() { bannersOn.toggle() }

    private func sizeMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        item.subtitle = critterSize.title
        let submenu = NSMenu()
        submenu.delegate = self
        submenu.autoenablesItems = false
        for size in CritterSize.allCases {
            let choice = NSMenuItem(title: size.title, action: #selector(chooseSize(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = size.rawValue
            choice.state = size == critterSize ? .on : .off
            submenu.addItem(choice)
        }
        item.submenu = submenu
        return item
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = CritterSize(rawValue: raw) else { return }
        critterSize = size
        lastPose = nil
        updateButton()
    }

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
            NSLog("Nudge Lamp: login item change failed: \(error.localizedDescription)")
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
