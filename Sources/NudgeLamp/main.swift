import NudgeLampCore
import AppKit
import ServiceManagement

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
if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    try DocRenderer.render(to: directory)
    print("Wrote critter animations to \(directory.path)")
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
