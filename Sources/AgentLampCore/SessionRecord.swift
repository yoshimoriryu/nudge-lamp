import Foundation

/// One Claude Code session, as written by Claude Code to `~/.claude/sessions/<pid>.json`.
///
/// The file format is internal to Claude Code and undocumented, so every field
/// except `pid`, `sessionId` and `cwd` is optional.
public struct SessionRecord: Decodable, Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var name: String?
    /// "interactive", "bg", "daemon" or "daemon-worker".
    public var kind: String?
    /// "busy", "shell", "idle" or "waiting".
    public var status: String?
    /// Why a "waiting" session is blocked, for example a permission dialog.
    public var waitingFor: String?
    /// Milliseconds since 1970.
    public var startedAt: Double?
    /// Milliseconds since 1970.
    public var statusUpdatedAt: Double?

    public init(
        pid: Int32,
        sessionId: String,
        cwd: String,
        name: String? = nil,
        kind: String? = "interactive",
        status: String?,
        waitingFor: String? = nil,
        startedAt: Double? = nil,
        statusUpdatedAt: Double? = nil
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.name = name
        self.kind = kind
        self.status = status
        self.waitingFor = waitingFor
        self.startedAt = startedAt
        self.statusUpdatedAt = statusUpdatedAt
    }

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public var statusChangedAt: Date {
        Date(milliseconds: statusUpdatedAt ?? startedAt ?? 0)
    }

    public var startDate: Date? {
        startedAt.map(Date.init(milliseconds:))
    }

    /// Sessions with a terminal the user can answer in. Daemon processes are skipped.
    public var isUserFacing: Bool {
        kind == nil || kind == "interactive" || kind == "bg"
    }
}

extension Date {
    public init(milliseconds: Double) {
        self.init(timeIntervalSince1970: milliseconds / 1000)
    }
}
