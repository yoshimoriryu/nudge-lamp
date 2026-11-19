import AppKit
import NudgeLampCore

/// Terminals whose AppleScript dictionary exposes each tab's tty, so Nudge Lamp can tell which
/// session you are looking at and jump to the exact tab. The first call to each one triggers
/// the macOS Automation prompt for that app.
@MainActor
enum ScriptableTerminal: CaseIterable {
    case iTerm2, terminal, ghostty

    nonisolated var bundleID: String {
        switch self {
        case .iTerm2: "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    nonisolated var name: String {
        switch self {
        case .iTerm2: "iTerm2"
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        }
    }

    init?(bundleID: String?) {
        guard let match = Self.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }

    /// The scriptable terminal in front of the user, if any.
    static var frontmost: ScriptableTerminal? {
        ScriptableTerminal(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    // Compiled once, because the focus check can run every second.
    private static let focusScripts: [ScriptableTerminal: NSAppleScript] = Dictionary(
        uniqueKeysWithValues: allCases.compactMap { terminal in
            NSAppleScript(source: terminal.focusSource).map { (terminal, $0) }
        }
    )

    private var focusSource: String {
        switch self {
        case .iTerm2:
            "tell application id \"\(bundleID)\" to get tty of current session of current window"
        case .terminal:
            "tell application id \"\(bundleID)\" to get tty of selected tab of front window"
        case .ghostty:
            "tell application id \"\(bundleID)\" to get tty of focused terminal of selected tab of front window"
        }
    }

    /// The tty of the tab the user is looking at in this terminal.
    func focusedTTY() -> String? {
        guard let script = Self.focusScripts[self] else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    /// Brings the window, tab and split pane that own `tty` to the front.
    /// `tty` comes from devname(3), so it never contains a quote.
    @discardableResult
    func reveal(tty: String) -> Bool {
        let body: String
        switch self {
        case .iTerm2:
            body = """
                repeat with w in windows
                  repeat with t in tabs of w
                    repeat with s in sessions of t
                      if tty of s is "\(tty)" then
                        tell w to select
                        tell t to select
                        tell s to select
                        activate
                        return true
                      end if
                    end repeat
                  end repeat
                end repeat
                """
        case .terminal:
            body = """
                repeat with w in windows
                  repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                      set selected tab of w to t
                      set index of w to 1
                      activate
                      return true
                    end if
                  end repeat
                end repeat
                """
        case .ghostty:
            body = """
                repeat with t in terminals
                  if tty of t is "\(tty)" then
                    focus t
                    activate
                    return true
                  end if
                end repeat
                """
        }
        let source = "tell application id \"\(bundleID)\"\n\(body)\nend tell\nreturn false"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && (result?.booleanValue ?? false)
    }
}

enum Terminals {
    /// The app a session runs in, found by walking up its parent processes until one is a
    /// regular app. Works for any terminal, including the VS Code terminal, Warp and kitty.
    /// Returns nil for sessions under a detached tmux or screen server.
    static func owningApp(of pid: Int32) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<16 {
            guard let parent = ProcessLookup.parent(of: current), parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent), app.activationPolicy == .regular {
                return app
            }
            current = parent
        }
        return nil
    }

    /// Jumps to a session: the exact tab in iTerm2, Terminal or Ghostty, or the owning app
    /// anywhere else. Returns a short description of what happened, for `--reveal`.
    @MainActor
    @discardableResult
    static func reveal(pid: Int32) -> String {
        let app = owningApp(of: pid)
        if let tty = ProcessLookup.tty(of: pid),
           let terminal = ScriptableTerminal(bundleID: app?.bundleIdentifier),
           terminal.reveal(tty: tty) {
            return "focused the \(tty) tab in \(terminal.name)"
        }
        guard let app else { return "no terminal app found for pid \(pid)" }
        app.activate()
        return "brought \(app.localizedName ?? app.bundleIdentifier ?? "the app") to the front"
    }
}
