import NudgeLampCore
import AppKit
import ServiceManagement

/// The value after a command-line flag. A flag given without a usable value exits with an error,
/// so a typo never starts a second menu bar instance.
func flagValue(_ flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
    let next = index + 1
    guard next < CommandLine.arguments.count, !CommandLine.arguments[next].hasPrefix("--") else {
        FileHandle.standardError.write(Data("\(flag) needs a value\n".utf8))
        exit(2)
    }
    return CommandLine.arguments[next]
}

// `NudgeLamp --print` lists sessions once and exits. Handy for checking what the lamp sees.
if CommandLine.arguments.contains("--print") {
    guard let claude = ClaudeAgents.locate() else {
        print("Claude Code CLI not found")
        exit(1)
    }
    let records = try ClaudeAgents.parse(
        ClaudeAgents.run(claude: claude),
        changedAt: SessionFolder.modificationDates()
    )
    var tracker = Tracker()
    let views = tracker.update(records, now: Date()).views
    if views.isEmpty { print("No Claude Code sessions running") }
    for view in views {
        let record = view.record
        let tty = ProcessLookup.tty(of: record.pid) ?? "-"
        let raw = [record.status, record.waitingFor].compactMap { $0 }.joined(separator: ": ")
        print("\(view.state)\t\(record.displayName)\t\(raw)\t\(tty)\t\(record.cwd)")
    }
    exit(0)
}

// `install.sh --uninstall` runs this first, so the login item does not outlive the app.
if CommandLine.arguments.contains("--unregister-login-item") {
    do {
        try SMAppService.mainApp.unregister()
        print("Removed Nudge Lamp from login items")
    } catch {
        print("Login item was not registered: \(error.localizedDescription)")
    }
    exit(0)
}

// `NudgeLamp --render <dir>` writes the critter animations as GIFs plus a contact sheet.
if let path = flagValue("--render") {
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try DocRenderer.render(to: directory)
    print("Wrote critter animations to \(directory.path)")
    exit(0)
}

// `NudgeLamp --reveal <pid>` jumps to that session's terminal tab the way a menu click does.
// Launch it through `open` so macOS checks the app's own Automation permission.
if let value = flagValue("--reveal") {
    guard let pid = Int32(value) else {
        FileHandle.standardError.write(Data("--reveal needs a process ID, got \(value)\n".utf8))
        exit(2)
    }
    print(Terminals.reveal(pid: pid))
    // Give the window server a moment to switch apps, then report what is in front.
    Thread.sleep(forTimeInterval: 0.8)
    let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
    let focused = ScriptableTerminal.frontmost?.focusedTTY() ?? "n/a"
    print("frontmost app: \(front), focused tty: \(focused), session tty: \(ProcessLookup.tty(of: pid) ?? "none")")
    exit(0)
}

// `NudgeLamp --doctor` prints a setup report. See Doctor.printReport for how to launch it.
if CommandLine.arguments.contains("--doctor") {
    Task {
        await Doctor.printReport()
        exit(0)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
