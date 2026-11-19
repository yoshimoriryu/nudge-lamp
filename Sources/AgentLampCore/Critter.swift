import Foundation

/// The critter's overall mood, one per lamp state.
public enum CritterMood: Sendable, CaseIterable {
    case idle, working, finished, blocked

    public init(_ state: LampState) {
        switch state {
        case .idle: self = .idle
        case .working: self = .working
        case .finished: self = .finished
        case .blocked: self = .blocked
        }
    }
}

/// One frame of the critter, described in sprite terms. The app turns it into pixels.
public struct CritterPose: Hashable, Sendable {
    public enum Eyes: Hashable, Sendable {
        case open(dx: Int, dy: Int)
        case closed
        case happy
        case wide
    }

    public enum Arm: Hashable, Sendable {
        case down, side, up, forward
    }

    public enum Tip: Hashable, Sendable {
        case dim, glow, bright, red, yellow
    }

    public enum Badge: Hashable, Sendable {
        case exclamation
        case sparkle(big: Bool)
        case dots(Int)
        case zee(step: Int)
    }

    public var dx = 0
    public var dy = 0
    public var eyes: Eyes = .open(dx: 0, dy: 0)
    public var mouth = false
    public var leftArm: Arm = .side
    public var rightArm: Arm = .side
    public var leftFootUp = false
    public var rightFootUp = false
    public var antennaLean = 0
    public var antennaDroop = false
    public var tip: Tip = .glow
    public var badge: Badge?
    public var dimmed = false

    public init() {}
}

/// Animation loops. Each mood has three, so the critter does not repeat itself all day.
public enum CritterVariant: String, CaseIterable, Sendable {
    case walk, type, think
    case jump, wave, shake
    case cheer, tap, lookAround
    case sleep, blink, daydream

    public static func variants(for mood: CritterMood) -> [CritterVariant] {
        switch mood {
        case .working: [.walk, .type, .think]
        case .blocked: [.jump, .wave, .shake]
        case .finished: [.cheer, .tap, .lookAround]
        case .idle: [.sleep, .blink, .daydream]
        }
    }

    /// The pose `t` frames into the loop, at `CritterAnimator.fps`.
    public func pose(at t: Int) -> CritterPose {
        var p = CritterPose()
        let redBlink: CritterPose.Tip = (t / 2) % 2 == 0 ? .red : .bright

        switch self {
        case .walk:
            let phase = (t / 2) % 4
            p.leftFootUp = phase == 0
            p.rightFootUp = phase == 2
            p.dy = phase % 2 == 0 ? -1 : 0
            p.leftArm = phase == 2 ? .down : .side
            p.rightArm = phase == 0 ? .down : .side
            p.antennaLean = phase == 0 ? -1 : (phase == 2 ? 1 : 0)
            p.eyes = .open(dx: 1, dy: 0)

        case .type:
            let phase = t % 4
            p.leftArm = phase == 0 ? .forward : .down
            p.rightArm = phase == 2 ? .forward : .down
            p.eyes = t % 40 == 39 ? .closed : .open(dx: 0, dy: 1)
            p.tip = (t / 2) % 2 == 0 ? .glow : .bright

        case .think:
            p.eyes = .open(dx: 1, dy: -1)
            p.badge = .dots((t / 4) % 4)
            p.antennaLean = [0, 1, 0, -1][(t / 3) % 4]
            p.rightArm = .up
            p.tip = .bright

        case .jump:
            let arc = [0, -1, -2, -3, -3, -2, -1, 0, 0, 0]
            p.dy = arc[t % arc.count]
            p.leftArm = .up
            p.rightArm = .up
            p.leftFootUp = p.dy < -1
            p.rightFootUp = p.dy < -1
            p.eyes = .wide
            p.mouth = true
            p.tip = redBlink
            p.badge = .exclamation

        case .wave:
            let up = (t / 2) % 2 == 0
            p.leftArm = up ? .up : .side
            p.rightArm = up ? .side : .up
            p.dy = up ? -1 : 0
            p.eyes = .wide
            p.mouth = true
            p.tip = redBlink
            p.badge = .exclamation

        case .shake:
            let cycle = t % 12
            p.dx = cycle < 6 ? (cycle % 2 == 0 ? -1 : 1) : 0
            p.leftArm = .up
            p.rightArm = .up
            p.eyes = .wide
            p.mouth = true
            p.tip = redBlink
            p.badge = .exclamation

        case .cheer:
            let cycle = t % 12
            p.dy = cycle < 5 ? [0, -1, -2, -1, 0][cycle] : 0
            p.leftArm = .up
            p.rightArm = .up
            p.eyes = .happy
            p.tip = .yellow
            p.badge = .sparkle(big: (t / 3) % 2 == 0)

        case .tap:
            p.rightFootUp = (t / 3) % 2 == 0
            p.leftArm = .down
            p.eyes = t % 24 == 23 ? .closed : .open(dx: -1, dy: 0)
            p.tip = .yellow
            p.badge = .sparkle(big: false)

        case .lookAround:
            let look = [-1, 0, 1, 0][(t / 6) % 4]
            p.eyes = .open(dx: look, dy: 0)
            p.antennaLean = look
            p.tip = .yellow
            p.badge = .sparkle(big: (t / 6) % 2 == 0)

        case .sleep:
            p.eyes = .closed
            p.leftArm = .down
            p.rightArm = .down
            p.antennaDroop = true
            p.tip = .dim
            p.badge = .zee(step: (t / 6) % 3)
            p.dimmed = true

        case .blink:
            p.eyes = t % 32 >= 30 ? .closed : .open(dx: 0, dy: 0)
            p.leftArm = .down
            p.rightArm = .down
            p.tip = .dim
            p.dimmed = true

        case .daydream:
            let look = [0, 1, 1, 0, -1, -1][(t / 8) % 6]
            p.eyes = .open(dx: look, dy: -1)
            p.antennaLean = [0, 1, 0, -1][(t / 8) % 4]
            p.leftArm = .down
            p.tip = .dim
            p.dimmed = true
        }
        return p
    }
}

/// Picks a loop for the current mood and plays it, switching loops every 8 to 16 seconds.
public struct CritterAnimator: Sendable {
    public static let fps = 8.0

    public private(set) var mood: CritterMood
    public private(set) var variant: CritterVariant
    private var tick = 0
    private var ticksLeft = 0

    public init(mood: CritterMood = .idle) {
        self.mood = mood
        variant = CritterVariant.variants(for: mood)[0]
    }

    public mutating func next(
        mood: CritterMood,
        using rng: inout some RandomNumberGenerator
    ) -> CritterPose {
        if mood != self.mood || ticksLeft <= 0 {
            let options = CritterVariant.variants(for: mood)
            let fresh = mood == self.mood ? options.filter { $0 != variant } : options
            variant = fresh.randomElement(using: &rng) ?? options[0]
            self.mood = mood
            tick = 0
            ticksLeft = Int.random(in: 64...128, using: &rng)
        }
        defer {
            tick += 1
            ticksLeft -= 1
        }
        return variant.pose(at: tick)
    }

    public mutating func next(mood: CritterMood) -> CritterPose {
        var rng = SystemRandomNumberGenerator()
        return next(mood: mood, using: &rng)
    }
}
