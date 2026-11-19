import AgentLampCore
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

/// Checks the macOS permissions Agent Lamp depends on, and fixes what it can.
enum Doctor {
    static let notificationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.yoshimoriryu.agentlamp"
    )!
    static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )!

    /// Whether Agent Lamp may send Apple Events to iTerm2.
    /// With `askIfNeeded`, macOS shows its consent prompt and this call blocks until the user answers.
    static func iTermControl(askIfNeeded: Bool = false) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: ITerm.bundleID)
        guard let desc = target.aeDesc else { return .unavailable("unknown") }
        let wildcard = FourCharCode(typeWildCard)
        let status = AEDeterminePermissionToAutomateTarget(desc, wildcard, wildcard, askIfNeeded)
        switch status {
        case noErr: return .allowed
        case -1743: return .denied        // errAEEventNotPermitted
        case -1744: return .notAsked      // errAEEventWouldRequireUserConsent
        case -600: return .unavailable("iTerm2 is not running")   // procNotFound
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
    /// not the terminal's: `open -n -W --stdout $(tty) "Agent Lamp.app" --args --doctor`
    static func printReport() async {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let folder = SessionDirectory.defaultURL
        let folderExists = FileManager.default.fileExists(atPath: folder.path)
        let sessions = SessionDirectory.load()
        let rows: [(String, String)] = [
            ("Agent Lamp", version),
            ("Sessions folder", folderExists ? "\(folder.path), \(sessions.count) live" : "\(folder.path) missing"),
            ("iTerm2 control", iTermControl().label),
            ("Notifications", await notifications().label),
            ("Open at login", loginItem),
        ]
        for (name, value) in rows {
            print(name.padding(toLength: 17, withPad: " ", startingAt: 0) + value)
        }
    }
}
