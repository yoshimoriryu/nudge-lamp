import Foundation
import Testing
@testable import AgentLampCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }

private func session(
    _ status: String,
    id: String = "s1",
    startedAt: Date = t0,
    changedAt: Date,
    waitingFor: String? = nil
) -> SessionRecord {
    SessionRecord(
        pid: 42,
        sessionId: id,
        cwd: "/tmp/project",
        name: "project-\(id)",
        status: status,
        waitingFor: waitingFor,
        startedAt: ms(startedAt),
        statusUpdatedAt: ms(changedAt)
    )
}

@Suite struct TrackerTests {
    @Test func mapsRawStatusToBaseState() {
        #expect(Tracker.baseState(of: session("waiting", changedAt: t0)) == .blocked)
        #expect(Tracker.baseState(of: session("busy", changedAt: t0)) == .working)
        #expect(Tracker.baseState(of: session("shell", changedAt: t0)) == .working)
        #expect(Tracker.baseState(of: session("idle", changedAt: t0)) == .idle)
        #expect(Tracker.baseState(of: session("something-new", changedAt: t0)) == .idle)
    }

    @Test func freshSessionThatNeverRanIsIdle() {
        var tracker = Tracker()
        let now = t0.addingTimeInterval(30)
        let update = tracker.update([session("idle", changedAt: t0.addingTimeInterval(1))], now: now)
        #expect(update.views.first?.state == .idle)
        #expect(update.events.isEmpty)
    }

    @Test func staleIdleSessionIsIdle() {
        var tracker = Tracker()
        let changed = t0.addingTimeInterval(60)
        let update = tracker.update([session("idle", changedAt: changed)], now: changed.addingTimeInterval(3600))
        #expect(update.views.first?.state == .idle)
    }

    @Test func recentFinishSeenAtLaunchIsFinishedButNotAnnounced() {
        var tracker = Tracker()
        let changed = t0.addingTimeInterval(60)
        let update = tracker.update([session("idle", changedAt: changed)], now: changed.addingTimeInterval(120))
        #expect(update.views.first?.state == .finished)
        #expect(update.events.isEmpty)
    }

    @Test func busyThenIdleAnnouncesFinishedOnceAfterDebounce() {
        var tracker = Tracker(debounce: 1.5)
        let busyAt = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: busyAt)], now: busyAt)

        let idleAt = t0.addingTimeInterval(40)
        let idle = session("idle", changedAt: idleAt)
        let first = tracker.update([idle], now: idleAt)
        #expect(first.views.first?.state == .finished)
        #expect(first.events.isEmpty, "inside the debounce window")

        let second = tracker.update([idle], now: idleAt.addingTimeInterval(2))
        #expect(second.events == [LampEvent(state: .finished, record: idle)])

        let third = tracker.update([idle], now: idleAt.addingTimeInterval(3))
        #expect(third.events.isEmpty, "announced only once")
        #expect(third.views.first?.state == .finished, "stays lit until seen")
    }

    @Test func flickerShorterThanDebounceIsNotAnnounced() {
        var tracker = Tracker(debounce: 1.5)
        let at = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: at)], now: at)
        _ = tracker.update([session("waiting", changedAt: at.addingTimeInterval(1))], now: at.addingTimeInterval(1))
        let back = tracker.update([session("busy", changedAt: at.addingTimeInterval(2))], now: at.addingTimeInterval(2))
        #expect(back.events.isEmpty)
        #expect(back.views.first?.state == .working)
    }

    @Test func blockedIsAnnouncedWithReason() {
        var tracker = Tracker(debounce: 1.5)
        let at = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: at)], now: at)
        let blocked = session("waiting", changedAt: at.addingTimeInterval(5), waitingFor: "permission")
        _ = tracker.update([blocked], now: at.addingTimeInterval(5))
        let update = tracker.update([blocked], now: at.addingTimeInterval(7))
        #expect(update.events == [LampEvent(state: .blocked, record: blocked)])
        #expect(LampSummary(update.views).state == .blocked)
    }

    @Test func focusedTabSilencesAndClearsFinish() {
        var tracker = Tracker(debounce: 1.5)
        let at = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: at)], now: at)
        let idle = session("idle", changedAt: at.addingTimeInterval(20))
        let update = tracker.update([idle], now: at.addingTimeInterval(25), focused: ["s1"])
        #expect(update.views.first?.state == .idle)
        #expect(update.events.isEmpty)

        let later = tracker.update([idle], now: at.addingTimeInterval(30))
        #expect(later.views.first?.state == .idle, "leaving the tab does not relight it")
        #expect(later.events.isEmpty)
    }

    @Test func focusedBlockedStaysRedButIsNotAnnouncedLater() {
        var tracker = Tracker(debounce: 1.5)
        let at = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: at)], now: at)
        let blocked = session("waiting", changedAt: at.addingTimeInterval(5))
        let seen = tracker.update([blocked], now: at.addingTimeInterval(8), focused: ["s1"])
        #expect(seen.views.first?.state == .blocked)
        #expect(seen.events.isEmpty)
        let away = tracker.update([blocked], now: at.addingTimeInterval(12))
        #expect(away.events.isEmpty)
    }

    @Test func acknowledgeClearsFinished() {
        var tracker = Tracker()
        let at = t0.addingTimeInterval(10)
        _ = tracker.update([session("busy", changedAt: at)], now: at)
        let idle = session("idle", changedAt: at.addingTimeInterval(5))
        _ = tracker.update([idle], now: at.addingTimeInterval(5))
        tracker.acknowledge(sessionId: "s1")
        let update = tracker.update([idle], now: at.addingTimeInterval(10))
        #expect(update.views.first?.state == .idle)
        #expect(update.events.isEmpty)
    }

    @Test func summaryPicksMostUrgentStateAndCountsSessionsThatNeedYou() {
        var tracker = Tracker()
        let now = t0.addingTimeInterval(100)
        let update = tracker.update([
            session("busy", id: "a", changedAt: t0.addingTimeInterval(90)),
            session("waiting", id: "b", changedAt: t0.addingTimeInterval(80)),
            session("idle", id: "c", changedAt: t0.addingTimeInterval(1)),
        ], now: now)
        let summary = LampSummary(update.views)
        #expect(summary.state == .blocked)
        #expect(summary.needsYouCount == 1)
        #expect(update.views.map(\.record.sessionId) == ["b", "a", "c"])
    }
}

@Suite struct SessionDirectoryTests {
    @Test func decodesRealFileAndSkipsDaemonsAndJunk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-lamp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Shape copied from a Claude Code 2.1.328 session file.
        let real = #"""
        {"pid":13625,"sessionId":"abc123","cwd":"/Users/me/code","startedAt":1795054103471,"version":"2.1.328","kind":"interactive","entrypoint":"cli","name":"code-91","nameSource":"derived","status":"waiting","waitingFor":"permission","updatedAt":1795054111804,"statusUpdatedAt":1795054111804}
        """#
        let daemon = #"{"pid":1,"sessionId":"d","cwd":"/","kind":"daemon","status":"busy"}"#
        try real.write(to: dir.appendingPathComponent("13625.json"), atomically: true, encoding: .utf8)
        try daemon.write(to: dir.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("2.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: dir.appendingPathComponent("13625.abc.key"), atomically: true, encoding: .utf8)

        let records = SessionDirectory.load(from: dir, isAlive: { _ in true })
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.pid == 13625)
        #expect(record.displayName == "code-91")
        #expect(record.status == "waiting")
        #expect(record.waitingFor == "permission")
        #expect(record.statusChangedAt == Date(milliseconds: 1795054111804))
    }

    @Test func deadProcessIsDropped() {
        let ghost = SessionRecord(pid: 99_999_999, sessionId: "x", cwd: "/", status: "idle", startedAt: 0)
        #expect(ProcessLookup.isAlive(ghost) == false)
    }

    @Test func currentProcessIsAliveAndRecycledPidIsNot() {
        let pid = getpid()
        let start = ProcessLookup.startTime(of: pid)!
        let mine = SessionRecord(pid: pid, sessionId: "me", cwd: "/", status: "busy", startedAt: ms(start) + 200)
        #expect(ProcessLookup.isAlive(mine))
        let older = SessionRecord(pid: pid, sessionId: "old", cwd: "/", status: "busy", startedAt: ms(start) - 60_000)
        #expect(ProcessLookup.isAlive(older) == false, "file predates this process, so the PID was recycled")
    }
}

/// Deterministic generator so animator tests do not depend on luck.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite struct CritterTests {
    @Test func everyMoodHasThreeOwnVariants() {
        let all = CritterMood.allCases.flatMap { CritterVariant.variants(for: $0) }
        #expect(all.count == 12)
        #expect(Set(all).count == 12)
    }

    @Test func blockedAlwaysShowsExclamationAndFinishedAlwaysShowsYellowTip() {
        for t in 0..<200 {
            for variant in CritterVariant.variants(for: .blocked) {
                #expect(variant.pose(at: t).badge == .exclamation)
            }
            for variant in CritterVariant.variants(for: .finished) {
                #expect(variant.pose(at: t).tip == .yellow)
            }
        }
    }

    @Test func posesStayInsideTheSprite() {
        for variant in CritterVariant.allCases {
            for t in 0..<200 {
                let pose = variant.pose(at: t)
                #expect((-3...0).contains(pose.dy), "\(variant) jumps out of frame")
                #expect((-1...1).contains(pose.dx))
            }
        }
    }

    @Test func moodChangeSwitchesVariantImmediately() {
        var rng = SeededRandom(state: 7)
        var animator = CritterAnimator(mood: .idle)
        _ = animator.next(mood: .idle, using: &rng)
        _ = animator.next(mood: .blocked, using: &rng)
        #expect(CritterVariant.variants(for: .blocked).contains(animator.variant))
    }

    @Test func variantRotatesWithinMoodOverTime() {
        var rng = SeededRandom(state: 42)
        var animator = CritterAnimator(mood: .working)
        var seen = Set<CritterVariant>()
        for _ in 0..<2000 {
            _ = animator.next(mood: .working, using: &rng)
            seen.insert(animator.variant)
        }
        #expect(seen.count >= 2)
        #expect(seen.isSubset(of: Set(CritterVariant.variants(for: .working))))
    }
}
