import Foundation

/// The strip of menu bar the critter may walk along, as sprite origins in screen points.
public struct WanderTrack: Equatable, Sendable {
    /// Leftmost and rightmost x for the sprite's left edge.
    public let minX: Double
    public let maxX: Double
    /// Sprite positions whose center sits behind the camera notch. Nothing can be drawn there,
    /// so the critter hurries through and never stops inside it.
    public let tunnel: ClosedRange<Double>?

    public init(screenMinX: Double, screenMaxX: Double, notch: ClosedRange<Double>?, spriteWidth: Double) {
        minX = screenMinX
        maxX = max(screenMinX, screenMaxX - spriteWidth)
        let half = spriteWidth / 2
        tunnel = notch.map { ($0.lowerBound - half)...($0.upperBound - half) }
    }

    public func clamp(_ x: Double) -> Double { min(max(x, minX), maxX) }

    public func inTunnel(_ x: Double) -> Bool { tunnel?.contains(x) ?? false }

    /// A random spot to stroll to, never behind the notch.
    func randomSpot(using rng: inout some RandomNumberGenerator) -> Double {
        for _ in 0..<16 {
            let x = Double.random(in: minX...maxX, using: &rng)
            if !inTunnel(x) { return x }
        }
        return minX
    }
}

/// What to draw for one frame of a walk.
public struct WanderFrame: Equatable, Sendable {
    /// True while the critter is out of its menu bar slot. The slot then shows an empty socket.
    public var away: Bool
    /// The sprite's left edge in screen points.
    public var x: Double
    public var pose: CritterPose
    /// True for a moment after the critter hops back into its slot, so the slot can beam.
    public var homecoming = false
}

/// Walks the critter along the menu bar as an idle animation, and sends it running home
/// in a panic when the user clicks it or the lamp changes. Advance it once per animation frame.
public struct Wanderer: Sendable {
    public enum Activity: CaseIterable, Sendable {
        case lookAround, wave, stretch, nap
    }

    public enum Phase: Equatable, Sendable {
        case home
        case hopOut(Int)
        case walk(to: Double)
        case pause(Activity, tick: Int, left: Int)
        /// The outing is over and the critter strolls back.
        case strollHome
        /// Something happened: the critter dashes back at `speed` points per frame.
        case panicHome(speed: Double)
        case hopIn(Int)
    }

    /// How long things last, in frames at `CritterAnimator.fps`.
    public struct Timing: Sendable {
        public var outing: ClosedRange<Int>
        public var rest: ClosedRange<Int>
        public var pause: ClosedRange<Int>
        public var nap: ClosedRange<Int>

        /// Outings of 2 to 4 minutes with 1 to 3 minutes at home in between.
        public static let normal = Timing(outing: 960...1920, rest: 480...1440, pause: 24...64, nap: 80...160)
        /// Short rests, for trying the feature out.
        public static let demo = Timing(outing: 480...960, rest: 40...80, pause: 16...40, nap: 40...80)

        public init(outing: ClosedRange<Int>, rest: ClosedRange<Int>, pause: ClosedRange<Int>, nap: ClosedRange<Int>) {
            self.outing = outing
            self.rest = rest
            self.pause = pause
            self.nap = nap
        }
    }

    /// Sprite pixels per frame while strolling.
    public static let strollPixels = 2.0
    /// The slowest panic, in sprite pixels per frame. Farther away it runs faster.
    public static let panicPixels = 6.0
    /// A panicking critter gets home within this many frames from anywhere on the bar.
    public static let panicFrames = 24.0
    /// How long the bulb beams after plugging back in, in frames.
    public static let homecomingFrames = 16
    /// How much faster the critter moves while hidden behind the notch.
    public static let tunnelBoost = 4.0

    static let hopArc = [-1, -2, -3, -3, -2, -1, 0]

    public private(set) var phase: Phase = .home
    public private(set) var x = 0.0
    public var timing: Timing
    private var tick = 0
    private var facing = 1
    private var outingLeft = 0
    private var restLeft = 0
    private var homecomingLeft = 0

    public init(timing: Timing = .normal) {
        self.timing = timing
    }

    public var isHome: Bool { phase == .home }

    /// Puts the critter back in its slot at once, for example when walking is turned off.
    public mutating func comeHomeNow(using rng: inout some RandomNumberGenerator) {
        phase = .home
        homecomingLeft = 0
        restLeft = Int.random(in: timing.rest, using: &rng)
    }

    public mutating func comeHomeNow() {
        var rng = SystemRandomNumberGenerator()
        comeHomeNow(using: &rng)
    }

    /// Advances one frame.
    /// - Parameters:
    ///   - mayWander: true once the lamp has been quiet and untouched for a while.
    ///     Turning false sends a wandering critter dashing home.
    ///   - mood: the lamp's mood. The bulb keeps this color while out walking.
    ///   - home: the slot's x in screen points.
    ///   - points: screen points per sprite pixel.
    public mutating func step(
        mayWander: Bool,
        mood: CritterMood,
        home: Double,
        track: WanderTrack,
        points: Double,
        using rng: inout some RandomNumberGenerator
    ) -> WanderFrame {
        tick += 1

        if phase == .home {
            x = home
            if restLeft > 0 { restLeft -= 1 }
            if homecomingLeft > 0 { homecomingLeft -= 1 }
            guard mayWander, restLeft <= 0 else {
                return WanderFrame(away: false, x: home, pose: CritterPose(), homecoming: homecomingLeft > 0)
            }
            homecomingLeft = 0
            outingLeft = Int.random(in: timing.outing, using: &rng)
            phase = .hopOut(0)
        }

        if !mayWander {
            switch phase {
            case .hopOut, .walk, .pause, .strollHome:
                let fastest = abs(x - home) / Self.panicFrames
                phase = .panicHome(speed: max(Self.panicPixels * points, fastest))
            default:
                break
            }
        }
        if outingLeft > 0 { outingLeft -= 1 }
        x = track.clamp(x)

        let bulb = Self.bulb(for: mood)
        let current = phase
        var pose: CritterPose
        switch current {
        case .home:
            return WanderFrame(away: false, x: home, pose: CritterPose())

        case .hopOut(let t):
            x = home
            pose = Self.hop(t, bulb: bulb)
            phase = t + 1 < Self.hopArc.count ? .hopOut(t + 1) : .walk(to: track.randomSpot(using: &rng))

        case .walk(let target):
            let arrived = move(toward: target, stride: Self.strollPixels * points, track: track)
            pose = Self.walk(tick, facing: facing, bulb: bulb)
            if arrived {
                // Naps only happen with the lights off, when nothing is running.
                let choices = Activity.allCases.filter { $0 != .nap || mood == .idle }
                let activity = choices.randomElement(using: &rng) ?? .lookAround
                let length = Int.random(in: activity == .nap ? timing.nap : timing.pause, using: &rng)
                phase = .pause(activity, tick: 0, left: length)
            }

        case .pause(let activity, let t, let left):
            pose = Self.activity(activity, t, bulb: bulb)
            if left > 1 {
                phase = .pause(activity, tick: t + 1, left: left - 1)
            } else if outingLeft <= 0 {
                phase = .strollHome
            } else {
                phase = .walk(to: track.randomSpot(using: &rng))
            }

        case .strollHome:
            let arrived = move(toward: home, stride: Self.strollPixels * points, track: track)
            pose = Self.walk(tick, facing: facing, bulb: bulb)
            if arrived { phase = .hopIn(0) }

        case .panicHome(let speed):
            let arrived = move(toward: home, stride: speed, track: track)
            pose = Self.panic(tick, facing: facing, bulb: bulb)
            if arrived { phase = .hopIn(0) }

        case .hopIn(let t):
            x = home
            pose = Self.hop(t, bulb: bulb)
            if t + 1 >= Self.hopArc.count {
                phase = .home
                homecomingLeft = Self.homecomingFrames
                restLeft = Int.random(in: timing.rest, using: &rng)
            } else {
                phase = .hopIn(t + 1)
            }
        }
        // Unplugged while out. The last frames of the hop back land in the socket and light up.
        if case .hopIn(let t) = current, t >= Self.hopArc.count - 2 {
            pose.glow = 2
        } else {
            pose.unlit = true
        }
        return WanderFrame(away: true, x: x, pose: pose)
    }

    public mutating func step(
        mayWander: Bool, mood: CritterMood, home: Double, track: WanderTrack, points: Double
    ) -> WanderFrame {
        var rng = SystemRandomNumberGenerator()
        return step(mayWander: mayWander, mood: mood, home: home, track: track, points: points, using: &rng)
    }

    /// Moves toward `target` by up to `stride` points and reports whether the critter got there.
    private mutating func move(toward target: Double, stride: Double, track: WanderTrack) -> Bool {
        let goal = track.clamp(target)
        let step = stride * (track.inTunnel(x) ? Self.tunnelBoost : 1)
        let distance = goal - x
        if distance != 0 { facing = distance > 0 ? 1 : -1 }
        if abs(distance) <= step {
            x = goal
            return true
        }
        x += step * Double(facing)
        return false
    }

    // MARK: Poses

    /// Out of its slot the bulb keeps the lamp's color. With nothing running it glows a soft cream.
    static func bulb(for mood: CritterMood) -> CritterPose.Bulb {
        switch mood {
        case .idle: .cream
        case .working: .green
        case .finished: .amber
        case .blocked: .red
        }
    }

    static func walk(_ t: Int, facing: Int, bulb: CritterPose.Bulb) -> CritterPose {
        var p = CritterPose()
        let phase = t % 4
        p.leftFootUp = phase == 0
        p.rightFootUp = phase == 2
        p.dy = phase % 2 == 0 ? -1 : 0
        p.leftArm = phase == 2 ? .down : .side
        p.rightArm = phase == 0 ? .down : .side
        p.eyes = .open(dx: facing, dy: 0)
        p.bulb = bulb
        return p
    }

    /// Arms flailing, feet a blur, eyes wide and a drop of sweat flying off.
    static func panic(_ t: Int, facing: Int, bulb: CritterPose.Bulb) -> CritterPose {
        var p = CritterPose()
        let up = t % 2 == 0
        p.leftFootUp = up
        p.rightFootUp = !up
        p.dy = up ? -1 : 0
        p.leftArm = up ? .up : .side
        p.rightArm = up ? .side : .up
        p.eyes = .wide
        p.mouth = true
        p.bulb = bulb
        p.badge = .sweat(step: t % 3)
        return p
    }

    static func hop(_ t: Int, bulb: CritterPose.Bulb) -> CritterPose {
        var p = CritterPose()
        p.dy = hopArc[min(t, hopArc.count - 1)]
        p.leftArm = .up
        p.rightArm = .up
        p.leftFootUp = p.dy < -1
        p.rightFootUp = p.dy < -1
        p.eyes = .happy
        p.bulb = bulb
        return p
    }

    static func activity(_ activity: Activity, _ t: Int, bulb: CritterPose.Bulb) -> CritterPose {
        var p = CritterPose()
        p.bulb = bulb
        switch activity {
        case .lookAround:
            p.eyes = .open(dx: [-1, 0, 1, 0][(t / 6) % 4], dy: 0)
            p.leftArm = .down
            p.rightArm = .down
        case .wave:
            let up = (t / 2) % 2 == 0
            p.rightArm = up ? .up : .side
            p.eyes = .happy
        case .stretch:
            let up = (t / 8) % 2 == 0
            p.leftArm = up ? .up : .side
            p.rightArm = up ? .up : .side
            p.eyes = up ? .closed : .open(dx: 0, dy: 0)
            p.mouth = up
        case .nap:
            p.eyes = .closed
            p.leftArm = .down
            p.rightArm = .down
            p.bulb = .off
            p.badge = .zee(step: (t / 6) % 3)
            p.dimmed = true
        }
        return p
    }
}

extension CritterPose {
    /// The empty slot left behind while the critter is out walking.
    public static var socket: CritterPose {
        var p = CritterPose()
        p.socketOnly = true
        p.dimmed = true
        return p
    }
}
