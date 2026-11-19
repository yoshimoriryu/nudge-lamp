import Foundation

/// What the lamp shows for one session. Higher raw values win the menu bar icon.
public enum LampState: Int, Comparable, Sendable {
    /// Sitting at the prompt and already seen by the user.
    case idle = 0
    /// Running a turn or a shell command.
    case working
    /// Finished a turn the user has not looked at yet.
    case finished
    /// Stopped mid-turn on a permission prompt, question or other dialog.
    case blocked

    public static func < (lhs: LampState, rhs: LampState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var needsYou: Bool {
        self == .finished || self == .blocked
    }
}

public struct SessionView: Equatable, Sendable {
    public let record: SessionRecord
    public let state: LampState

    public init(record: SessionRecord, state: LampState) {
        self.record = record
        self.state = state
    }
}

/// A session that just started needing the user and should be announced.
public struct LampEvent: Equatable, Sendable {
    public let state: LampState
    public let record: SessionRecord
}

public struct LampSummary: Equatable, Sendable {
    public let state: LampState
    public let needsYouCount: Int

    public init(_ views: [SessionView]) {
        state = views.map(\.state).max() ?? .idle
        needsYouCount = views.filter(\.state.needsYou).count
    }
}

/// Turns raw session records into lamp states and decides when to announce them.
///
/// Claude Code reports "idle" both for a turn that just ended and for a session
/// nobody has touched in hours. The tracker tells them apart by remembering
/// whether it saw the session working since the user last looked at it.
public struct Tracker: Sendable {
    /// How long a state must hold before it is announced. Filters out flicker.
    public var debounce: TimeInterval
    /// An idle session older than this when first seen counts as already seen.
    public var staleAfter: TimeInterval

    private var memory: [String: Memory] = [:]

    private struct Memory: Sendable {
        /// The session worked since the user last looked at it.
        var finishPending: Bool
        var announced: Bool
        var state: LampState
        var enteredAt: Date
    }

    public init(debounce: TimeInterval = 1.5, staleAfter: TimeInterval = 600) {
        self.debounce = debounce
        self.staleAfter = staleAfter
    }

    /// - Parameter focused: session IDs whose terminal tab is in front of the user right now.
    public mutating func update(
        _ records: [SessionRecord],
        now: Date,
        focused: Set<String> = []
    ) -> (views: [SessionView], events: [LampEvent]) {
        let present = Set(records.map(\.sessionId))
        memory = memory.filter { present.contains($0.key) }

        var views: [SessionView] = []
        var events: [LampEvent] = []

        for record in records {
            let id = record.sessionId
            let base = Self.baseState(of: record)
            let isFocused = focused.contains(id)
            var m = memory[id] ?? firstSight(record, base: base, now: now)

            if base != .idle {
                m.finishPending = true
            } else if isFocused {
                m.finishPending = false
            }

            let state: LampState = (base == .idle && m.finishPending) ? .finished : base
            if state != m.state {
                m.state = state
                m.enteredAt = now
                m.announced = false
            }
            if state.needsYou && isFocused {
                m.announced = true
            }
            if state.needsYou && !m.announced && now.timeIntervalSince(m.enteredAt) >= debounce {
                m.announced = true
                events.append(LampEvent(state: state, record: record))
            }

            memory[id] = m
            views.append(SessionView(record: record, state: state))
        }

        views.sort { a, b in
            if a.state != b.state { return a.state > b.state }
            return a.record.statusChangedAt > b.record.statusChangedAt
        }
        return (views, events)
    }

    /// Marks a finished session as seen, for example after the user clicks it.
    public mutating func acknowledge(sessionId: String) {
        guard var m = memory[sessionId] else { return }
        m.finishPending = false
        m.announced = true
        if m.state == .finished { m.state = .idle }
        memory[sessionId] = m
    }

    public mutating func acknowledgeAll() {
        for id in memory.keys { acknowledge(sessionId: id) }
    }

    public static func baseState(of record: SessionRecord) -> LampState {
        switch record.status {
        case "waiting": .blocked
        case "busy", "shell": .working
        default: .idle
        }
    }

    /// States that already existed when the tracker first sees a session are never announced.
    private func firstSight(_ record: SessionRecord, base: LampState, now: Date) -> Memory {
        let changed = record.statusChangedAt
        let stale = now.timeIntervalSince(changed) > staleAfter
        // A session that has not changed state since startup has not run a turn yet.
        let neverRan = record.startDate.map { changed.timeIntervalSince($0) < 5 } ?? true
        let pending = base != .idle || !(stale || neverRan)
        let state: LampState = (base == .idle && pending) ? .finished : base
        return Memory(finishPending: pending, announced: true, state: state, enteredAt: now)
    }
}
