import NudgeLampCore
import AppKit
import CoreServices
import ServiceManagement
import UserNotifications

enum Permission: Equatable, Sendable {
    case allowed
    case denied
    case notAsked
    case unavailable(String)

    var label: String {
        switch self {
        case .allowed: "allowed"
        case .denied: "denied"
        case .notAsked: "not asked yet"
        case .unavailable(let reason): reason
        }
    }
}

/// Checks the macOS permissions Nudge Lamp depends on, and fixes what it can.
enum Doctor {
    static let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.yoshimoriryu.nudgelamp"
    )!
    static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    /// Whether Nudge Lamp may send Apple Events to `terminal`.
    /// With `askIfNeeded`, macOS shows its consent prompt and this call blocks until the user answers.
    static func control(of terminal: ScriptableTerminal, askIfNeeded: Bool = false) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: terminal.bundleID)
        guard let desc = target.aeDesc else { return .unavailable("unknown") }
        let wildcard = FourCharCode(typeWildCard)
        let status = AEDeterminePermissionToAutomateTarget(desc, wildcard, wildcard, askIfNeeded)
        switch status {
        case noErr: return .allowed
        case -1743: return .denied        // errAEEventNotPermitted
        case -1744: return .notAsked      // errAEEventWouldRequireUserConsent
        case -600: return .unavailable("\(terminal.name) is not running")   // procNotFound
        default: return .unavailable("error \(status)")
        }
    }

    static func notifications() async -> Permission {
        guard Bundle.main.bundleIdentifier != nil else { return .unavailable("not running as an app") }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            // Allowed with the alert style set to None still means no banners.
            return settings.alertSetting == .enabled ? .allowed : .unavailable("allowed, but banners are off")
        case .denied:
            return .denied
        case .notDetermined:
            return .notAsked
        @unknown default:
            return .unavailable("unknown")
        }
    }

    static var loginItem: String {
        switch SMAppService.mainApp.status {
        case .enabled: "enabled"
        case .requiresApproval: "waiting for approval in System Settings > General > Login Items"
        case .notRegistered: "off"
        case .notFound: "not found"
        @unknown default: "unknown"
        }
    }

    /// Prints a setup report. Launch through `open` so macOS checks the app's own permissions,
    /// not the terminal's: `open -n -W --stdout $(tty) "Nudge Lamp.app" --args --doctor`
    static func printReport() async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let claude = ClaudeAgents.locate()
        var sessions = "Claude Code CLI not found"
        if let claude {
            let start = Date()
            do {
                let count = try ClaudeAgents.parse(ClaudeAgents.run(claude: claude)).count
                sessions = "\(count) live, read in \(Int(Date().timeIntervalSince(start) * 1000)) ms"
            } catch {
                sessions = "claude agents --json failed: \(error)"
            }
        }
        let rows: [(String, String)] = [
            ("Nudge Lamp", version),
            ("Claude Code CLI", claude?.path ?? "not found"),
            ("Sessions", sessions),
        ] + ScriptableTerminal.allCases.map { ("\($0.name) control", control(of: $0).label) } + [
            ("Notifications", await notifications().label),
            ("Open at login", loginItem),
        ]
        for (name, value) in rows {
            print(name.padding(toLength: 17, withPad: " ", startingAt: 0) + value)
        }
    }
}
