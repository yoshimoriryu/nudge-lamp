import AgentLampCore
import AppKit

// `AgentLamp --print` lists sessions once and exits. Handy for checking what the lamp sees.
if CommandLine.arguments.contains("--print") {
    var tracker = Tracker()
    let views = tracker.update(SessionDirectory.load(), now: Date()).views
    if views.isEmpty { print("No Claude Code sessions running") }
    for view in views {
        let record = view.record
        let tty = ProcessLookup.tty(of: record.pid) ?? "-"
        let raw = [record.status, record.waitingFor].compactMap { $0 }.joined(separator: ": ")
        print("\(view.state)\t\(record.displayName)\t\(raw)\t\(tty)\t\(record.cwd)")
    }
    exit(0)
}

// `AgentLamp --render <dir>` writes the critter animations as GIFs plus a contact sheet.
if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    try DocRenderer.render(to: directory)
    print("Wrote critter animations to \(directory.path)")
    exit(0)
}

// `AgentLamp --doctor` prints a setup report. See Doctor.printReport for how to launch it.
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
