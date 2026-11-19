import Foundation

/// One live Claude Code session, as reported by `claude agents --json`.
public struct SessionRecord: Decodable, Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String
    public var name: String?
    /// "interactive" or "background".
    public var kind: String?
    /// "busy", "waiting" or "idle". Older builds also report "shell" while a shell command runs.
    public var status: String?
    /// Why a "waiting" session is blocked, for example "permission prompt".
    public var waitingFor: String?
    /// Milliseconds since 1970.
    public var startedAt: Double?
    /// Milliseconds since 1970. Taken from the session file's modification time, when known.
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

    /// Sessions the user can answer. Internal daemon processes are skipped.
    public var isUserFacing: Bool {
        kind == nil || kind == "interactive" || kind == "background" || kind == "bg"
    }
}

extension Date {
    public init(milliseconds: Double) {
        self.init(timeIntervalSince1970: milliseconds / 1000)
    }
}
