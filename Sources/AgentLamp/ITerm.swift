import AppKit

/// Talks to iTerm2 over AppleScript. The first call triggers the macOS Automation prompt.
@MainActor
enum ITerm {
    nonisolated static let bundleID = "com.googlecode.iterm2"

    private static let focusedTTYScript = NSAppleScript(source: """
        tell application id "\(bundleID)" to get tty of current session of current window
        """)

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    /// The tty of the iTerm2 session the user is looking at, or nil when iTerm2 is in the background.
    static func focusedTTY() -> String? {
        guard isFrontmost, let script = focusedTTYScript else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    /// Brings the iTerm2 window, tab and split pane that own `tty` to the front.
    @discardableResult
    static func reveal(tty: String) -> Bool {
        // `tty` comes from devname(3), so it never contains a quote.
        let source = """
            tell application id "\(bundleID)"
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
            end tell
            return false
            """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && (result?.booleanValue ?? false)
    }

    static func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
    }
}
