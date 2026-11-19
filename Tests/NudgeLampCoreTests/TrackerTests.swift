import Foundation
import Testing
@testable import NudgeLampCore

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

@Suite struct ClaudeAgentsTests {
    // Shape copied from `claude agents --json` in Claude Code 2.1.328, with names and IDs replaced.
    static let sample = Data(#"""
    [
      {"cwd":"/Users/me/old","kind":"background","id":"bg1","state":"blocked","sessionId":"s-bg","name":"Old task","startedAt":1795000000000},
      {"cwd":"/Users/me/api","kind":"interactive","pid":2398,"status":"idle","sessionId":"s-idle","name":"api-58","startedAt":1794445128648},
      {"cwd":"/Users/me/web","kind":"interactive","pid":13625,"status":"waiting","waitingFor":"permission prompt","sessionId":"s-wait","name":"web-91","startedAt":1795054103471},
      {"cwd":"/Users/me/cli","kind":"interactive","pid":19926,"status":"busy","startedAt":1795049895086}
    ]
    """#.utf8)

    @Test func keepsOnlySessionsWithALiveProcess() throws {
        let records = try ClaudeAgents.parse(Self.sample)
        #expect(records.map(\.pid) == [2398, 13625, 19926], "the background entry has no pid, so it is not running")
    }

    @Test func mapsDocumentedFields() throws {
        let waiting = try #require(try ClaudeAgents.parse(Self.sample).first { $0.pid == 13625 })
        #expect(waiting.status == "waiting")
        #expect(waiting.waitingFor == "permission prompt")
        #expect(waiting.displayName == "web-91")
        #expect(waiting.cwd == "/Users/me/web")
        #expect(Tracker.baseState(of: waiting) == .blocked)
    }

    @Test func fillsMissingSessionIdAndNameFallbacks() throws {
        let unnamed = try #require(try ClaudeAgents.parse(Self.sample).first { $0.pid == 19926 })
        #expect(unnamed.sessionId == "pid-19926")
        #expect(unnamed.displayName == "cli")
    }

    @Test func changeTimesComeFromTheSessionFolder() throws {
        let when = Date(timeIntervalSince1970: 1_795_054_111.804)
        let records = try ClaudeAgents.parse(Self.sample, changedAt: [13625: when])
        #expect(records.first { $0.pid == 13625 }?.statusChangedAt == when)
        let idle = try #require(records.first { $0.pid == 2398 })
        #expect(idle.statusChangedAt == idle.startDate, "falls back to the start time")
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try ClaudeAgents.parse(Data("not json".utf8)) }
    }

    @Test func emptyListMeansNoSessions() throws {
        #expect(try ClaudeAgents.parse(Data("[]".utf8)).isEmpty)
    }

    @Test func sessionFolderReadsModificationTimesByPid() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudge-lamp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("4242.json")
        try Data("{}".utf8).write(to: file)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        try Data("{}".utf8).write(to: dir.appendingPathComponent("4242.abc.key"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("notapid.json"))

        #expect(SessionFolder.modificationDates(in: dir) == [4242: stamp])
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

    @Test func bulbColorAndBadgeAlwaysMatchTheMood() {
        for t in 0..<200 {
            for variant in CritterVariant.variants(for: .blocked) {
                let pose = variant.pose(at: t)
                #expect(pose.badge == .exclamation)
                #expect(pose.bulb == .red || pose.bulb == .white)
            }
            for variant in CritterVariant.variants(for: .working) {
                let bulb = variant.pose(at: t).bulb
                #expect(bulb == .green || bulb == .mint)
            }
            for variant in CritterVariant.variants(for: .finished) {
                #expect(variant.pose(at: t).bulb == .amber)
            }
            for variant in CritterVariant.variants(for: .idle) {
                #expect(variant.pose(at: t).bulb == .off)
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
