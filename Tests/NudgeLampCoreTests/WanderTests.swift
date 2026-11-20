import Foundation
import Testing
@testable import NudgeLampCore

private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// This Mac's notched display: 1920 pt wide with the notch between 856 and 1064.
private let points = 1.5
private let width = 23 * points
private let track = WanderTrack(screenMinX: 0, screenMaxX: 1920, notch: 856...1064, spriteWidth: width)
private let home = 1500.0

/// Steps until the critter is at least `distance` points from home.
private func walkAway(_ w: inout Wanderer, _ rng: inout Seeded, distance: Double, mood: CritterMood = .idle) -> WanderFrame {
    var frame = w.step(mayWander: true, mood: mood, home: home, track: track, points: points, using: &rng)
    for _ in 0..<100_000 where abs(frame.x - home) < distance {
        frame = w.step(mayWander: true, mood: mood, home: home, track: track, points: points, using: &rng)
    }
    return frame
}

/// Steps with walking not allowed until the critter is home. Returns the frames it took.
private func callHome(_ w: inout Wanderer, _ rng: inout Seeded, mood: CritterMood = .idle) -> [WanderFrame] {
    var frames: [WanderFrame] = []
    while !w.isHome && frames.count < 1000 {
        frames.append(w.step(mayWander: false, mood: mood, home: home, track: track, points: points, using: &rng))
    }
    return frames
}

@Suite struct WanderTests {
    @Test func trackKeepsTheSpriteOnScreenAndMarksTheNotch() {
        #expect(track.minX == 0)
        #expect(track.maxX == 1920 - width)
        #expect(track.inTunnel(940))
        #expect(!track.inTunnel(800))
        #expect(!track.inTunnel(1100))
        #expect(track.clamp(5000) == track.maxX)
        #expect(track.clamp(-10) == 0)
    }

    @Test func staysHomeUntilTheLampIsQuiet() {
        var rng = Seeded(state: 1)
        var w = Wanderer()
        for _ in 0..<500 {
            let frame = w.step(mayWander: false, mood: .working, home: home, track: track, points: points, using: &rng)
            #expect(!frame.away)
        }
        #expect(w.isHome)
    }

    @Test func hopsOutAtHomeThenWalksAway() {
        var rng = Seeded(state: 2)
        var w = Wanderer()
        let first = w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng)
        #expect(first.away)
        #expect(first.x == home)
        #expect(first.pose.dy < 0)
        var left = false
        for _ in 0..<200 {
            let frame = w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng)
            #expect(frame.away)
            #expect((track.minX...track.maxX).contains(frame.x))
            if frame.x != home { left = true }
        }
        #expect(left)
    }

    @Test func keepsTheLampColorWhileWalking() {
        let cases: [(CritterMood, CritterPose.Bulb)] = [(.working, .green), (.blocked, .red), (.finished, .amber), (.idle, .cream)]
        for (mood, bulb) in cases {
            var rng = Seeded(state: 9)
            var w = Wanderer()
            for _ in 0..<2000 {
                let frame = w.step(mayWander: true, mood: mood, home: home, track: track, points: points, using: &rng)
                if frame.away && !frame.pose.dimmed {
                    #expect(frame.pose.bulb == bulb, "\(mood)")
                }
            }
        }
    }

    @Test func napsOnlyWhenNothingIsRunning() {
        var rng = Seeded(state: 10)
        var w = Wanderer(timing: .demo)
        for _ in 0..<20_000 {
            _ = w.step(mayWander: true, mood: .working, home: home, track: track, points: points, using: &rng)
            if case .pause(let activity, _, _) = w.phase {
                #expect(activity != .nap)
            }
        }
    }

    @Test func neverStopsBehindTheNotchAndHurriesThroughIt() {
        var rng = Seeded(state: 3)
        var w = Wanderer(timing: .demo)
        var lastX = home
        for _ in 0..<20_000 {
            let frame = w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng)
            if case .pause = w.phase {
                #expect(!track.inTunnel(frame.x))
            }
            if case .walk = w.phase, track.inTunnel(lastX), track.inTunnel(frame.x) {
                #expect(abs(abs(frame.x - lastX) - Wanderer.strollPixels * points * Wanderer.tunnelBoost) < 1e-9)
            }
            lastX = frame.x
        }
    }

    @Test func panicsHomeWhenCalledFromNearby() {
        var rng = Seeded(state: 4)
        var w = Wanderer()
        _ = walkAway(&w, &rng, distance: 30, mood: .blocked)
        let frames = callHome(&w, &rng, mood: .blocked)
        #expect(w.isHome)
        #expect(frames.contains { if case .sweat = $0.pose.badge { true } else { false } })
        #expect(frames.allSatisfy { $0.pose.bulb == .red })
        #expect(frames.count < 40)
    }

    @Test func runsHomeWithSweatAndDustFlyingBehind() {
        for seed: UInt64 in [12, 13, 14, 15] {
            var rng = Seeded(state: seed)
            var w = Wanderer()
            var body = walkAway(&w, &rng, distance: 300).x
            for frame in callHome(&w, &rng) {
                guard case .sweat(_, let facing) = frame.pose.badge else { continue }
                #expect(abs(home - frame.x) <= abs(home - body))
                #expect(facing == (home > body ? 1 : -1))
                // Dust only when a foot is on the ground, and always behind.
                if frame.pose.dust != 0 {
                    #expect(frame.pose.dy == 0)
                    #expect(frame.pose.dust == facing)
                }
                body = frame.x
            }
            #expect(w.isHome)
        }
    }

    @Test func panicsHomeWithinAboutThreeSecondsFromAnywhere() {
        var rng = Seeded(state: 5)
        var w = Wanderer()
        let start = walkAway(&w, &rng, distance: 1200)
        #expect(abs(start.x - home) >= 1200)
        let frames = callHome(&w, &rng)
        #expect(w.isHome)
        // The dash plus the hop back into the slot.
        #expect(frames.count <= Int(Wanderer.panicFrames) + Wanderer.hopArc.count + 1)
    }

    @Test func restsAtHomeAfterAnOuting() {
        var rng = Seeded(state: 6)
        var w = Wanderer(timing: .init(outing: 10...10, rest: 100...100, pause: 2...2, nap: 2...2))
        var ticks = 0
        _ = w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng)
        while !w.isHome && ticks < 10_000 {
            _ = w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng)
            ticks += 1
        }
        #expect(w.isHome)
        // Home for the whole rest, then out again.
        for _ in 0..<99 {
            #expect(!w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng).away)
        }
        #expect(w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng).away)
    }

    @Test func comeHomeNowEndsTheWalk() {
        var rng = Seeded(state: 7)
        var w = Wanderer()
        _ = walkAway(&w, &rng, distance: 30)
        #expect(!w.isHome)
        w.comeHomeNow(using: &rng)
        #expect(w.isHome)
        #expect(!w.step(mayWander: true, mood: .idle, home: home, track: track, points: points, using: &rng).away)
    }

    @Test func unpluggedWhileOutAndLightsUpOnLanding() {
        var rng = Seeded(state: 11)
        var w = Wanderer()
        let start = walkAway(&w, &rng, distance: 200, mood: .working)
        #expect(start.pose.unlit)
        #expect(start.pose.glow == 0)
        var frames: [WanderFrame] = []
        while !w.isHome && frames.count < 1000 {
            frames.append(w.step(mayWander: false, mood: .working, home: home, track: track, points: points, using: &rng))
        }
        let landing = frames.suffix(2)
        #expect(landing.allSatisfy { !$0.pose.unlit && $0.pose.glow == 2 })
        #expect(frames.dropLast(2).allSatisfy { $0.pose.unlit && $0.pose.glow == 0 })
        // Home now: the slot beams for a moment, then settles.
        var beaming = 0
        for _ in 0..<40 {
            let frame = w.step(mayWander: false, mood: .working, home: home, track: track, points: points, using: &rng)
            #expect(!frame.away)
            if frame.homecoming { beaming += 1 }
        }
        #expect(beaming == Wanderer.homecomingFrames - 1)
    }

    @Test func pluggedInBulbShinesOnlyWhileSomethingRuns() {
        let working = CritterVariant.type.pose(at: 0).plugged(mood: .working, tick: 0, homecoming: false)
        #expect(working.glow > 0)
        let idle = CritterVariant.sleep.pose(at: 0).plugged(mood: .idle, tick: 0, homecoming: false)
        #expect(idle.glow == 0)
        #expect(idle.bulb == .off)
        let back = CritterVariant.sleep.pose(at: 0).plugged(mood: .idle, tick: 0, homecoming: true)
        #expect(back.glow == 2)
        #expect(back.bulb == .cream)
        #expect(back.eyes == .happy)
        #expect(back.badge == nil)
        #expect(!back.dimmed)
    }

    @Test func walkingPosesStayInsideTheSprite() {
        for t in 0..<64 {
            let poses = [
                Wanderer.walk(t, facing: 1, bulb: .cream),
                Wanderer.panic(t, facing: -1, bulb: .red),
                Wanderer.hop(t, bulb: .cream),
            ] + Wanderer.Activity.allCases.map { Wanderer.activity($0, t, bulb: .cream) }
            for pose in poses {
                #expect((-3...0).contains(pose.dy))
                #expect((-1...1).contains(pose.dx))
            }
        }
    }
}
