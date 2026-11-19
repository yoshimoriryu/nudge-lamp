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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
