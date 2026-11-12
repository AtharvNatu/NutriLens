import CoreGraphics
import Foundation

// MARK: - Geometry helpers

struct P: Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    static func + (a: P, b: P) -> P { P(a.x + b.x, a.y + b.y) }
    static func - (a: P, b: P) -> P { P(a.x - b.x, a.y - b.y) }
    static func * (a: P, k: Double) -> P { P(a.x * k, a.y * k) }
    var length: Double { (x * x + y * y).squareRoot() }
    var cg: CGPoint { CGPoint(x: x, y: y) }
}

func dir(_ degrees: Double) -> P {
    let r = degrees * .pi / 180
    return P(cos(r), sin(r))
}

func angle(of v: P) -> Double { atan2(v.y, v.x) * 180 / .pi }

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func lerp(_ a: P, _ b: P, _ t: Double) -> P { P(lerp(a.x, b.x, t), lerp(a.y, b.y, t)) }

/// Two-bone inverse kinematics: the middle joint for a limb from `root` reaching `target`.
/// `bend` (+1/-1) picks which side the joint bends to.
func solveIK(root: P, target: P, l1: Double, l2: Double, bend: Double) -> (joint: P, end: P) {
    var d = target - root
    var dist = d.length
    let maxReach = l1 + l2 - 0.01
    let minReach = abs(l1 - l2) + 0.01
    if dist > maxReach { d = d * (maxReach / dist); dist = maxReach }
    if dist < minReach { d = d * (minReach / max(dist, 0.001)); dist = minReach }
    let base = angle(of: d)
    let cosA = min(1, max(-1, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
    let a = acos(cosA) * 180 / .pi
    let joint = root + dir(base + bend * a) * l1
    return (joint, root + d)
}

// MARK: - Body proportions (pixels, figure about 440 px tall)

enum Body {
    static let torso = 150.0      // hip → neck base
    static let shoulderAt = 0.9   // shoulders sit 90 % up the torso
    static let neck = 40.0        // neck base → head centre
    static let headRadius = 28.0
    static let upperArm = 82.0
    static let forearm = 76.0
    static let thigh = 108.0
    static let shin = 104.0
    static let foot = 42.0
    static let ankleHeight = 10.0
    static let ground = 70.0      // floor line y
    static let ankleY = ground + ankleHeight
}

// MARK: - Side-view pose

enum Limb {
    /// Absolute segment angles (degrees, 0 = right, 90 = up).
    case angles(Double, Double)
    /// Reach for a point; the middle joint bends toward `bend`.
    case ik(P, bend: Double)

    func interpolated(to other: Limb, _ t: Double) -> Limb {
        switch (self, other) {
        case let (.angles(a1, a2), .angles(b1, b2)): .angles(lerp(a1, b1, t), lerp(a2, b2, t))
        case let (.ik(p, bend), .ik(q, _)): .ik(lerp(p, q, t), bend: bend)
        default: t < 0.5 ? self : other
        }
    }
}

enum Anchor {
    case hip(P)
    /// Fix the neck base (shoulders) and hang the torso from it, e.g. a glute bridge.
    case neck(P)
    /// Fix the near ankle; the near leg must use `.angles`.
    case ankle(P)

    func interpolated(to other: Anchor, _ t: Double) -> Anchor {
        switch (self, other) {
        case let (.hip(a), .hip(b)): .hip(lerp(a, b, t))
        case let (.neck(a), .neck(b)): .neck(lerp(a, b, t))
        case let (.ankle(a), .ankle(b)): .ankle(lerp(a, b, t))
        default: t < 0.5 ? self : other
        }
    }
}

enum DumbbellStyle {
    case none
    /// Plates seen face-on (axis pointing at the camera): curls, presses, rows.
    case endOn
    /// Axis vertical in the picture plane: hammer curls, goblet hold.
    case upright
}

struct SidePose {
    var anchor: Anchor
    var torso: Double = 90
    /// Bows the spine: positive arches upward (cat), negative sags (cow).
    var torsoCurve: Double = 0
    var head: Double = 0
    var armN: Limb = .angles(-90, -90)
    var armF: Limb = .angles(-90, -90)
    var legN: Limb = .angles(-90, -90)
    var legF: Limb = .angles(-90, -90)
    var footN: Double = 0
    var footF: Double = 0
    /// Foreshortening for arms moving out of the picture plane (reverse fly).
    var armScale: Double = 1
    var dumbbellN: DumbbellStyle = .none
    var dumbbellF: DumbbellStyle = .none
    /// One dumbbell held in both hands between the wrists (goblet squat, overhead extension), held upright.
    var sharedDumbbell: Bool = false

    func interpolated(to o: SidePose, _ t: Double) -> SidePose {
        var p = self
        p.anchor = anchor.interpolated(to: o.anchor, t)
        p.torso = lerp(torso, o.torso, t)
        p.torsoCurve = lerp(torsoCurve, o.torsoCurve, t)
        p.head = lerp(head, o.head, t)
        p.armN = armN.interpolated(to: o.armN, t)
        p.armF = armF.interpolated(to: o.armF, t)
        p.legN = legN.interpolated(to: o.legN, t)
        p.legF = legF.interpolated(to: o.legF, t)
        p.footN = lerp(footN, o.footN, t)
        p.footF = lerp(footF, o.footF, t)
        p.armScale = lerp(armScale, o.armScale, t)
        return p
    }
}

/// Joint positions for drawing.
struct Skeleton {
    var hip, neck, shoulder, head, chestControl: P
    var elbowN, wristN, elbowF, wristF: P
    var kneeN, ankleN, toeN, kneeF, ankleF, toeF: P
}

/// Far-side limbs are drawn slightly offset so both sides read.
let farOffset = P(-7, 3)

func solve(_ pose: SidePose) -> Skeleton {
    let torsoVec = dir(pose.torso) * Body.torso
    let hip: P
    switch pose.anchor {
    case .hip(let h):
        hip = h
    case .neck(let n):
        hip = n - torsoVec
    case .ankle(let a):
        guard case let .angles(thigh, shin) = pose.legN else { fatalError("ankle anchor needs leg angles") }
        hip = a - dir(shin) * Body.shin - dir(thigh) * Body.thigh
    }
    let neck = hip + torsoVec
    let shoulder = hip + torsoVec * Body.shoulderAt
    let head = neck + dir(pose.torso + pose.head) * Body.neck
    // Perpendicular offset for a curved spine.
    let normal = dir(pose.torso + 90)
    let chestControl = (hip + neck) * 0.5 + normal * pose.torsoCurve

    func arm(_ limb: Limb, root: P) -> (P, P) {
        let l1 = Body.upperArm * pose.armScale, l2 = Body.forearm * pose.armScale
        switch limb {
        case let .angles(a, b):
            let e = root + dir(a) * l1
            return (e, e + dir(b) * l2)
        case let .ik(target, bend):
            let r = solveIK(root: root, target: target, l1: l1, l2: l2, bend: bend)
            return (r.joint, r.end)
        }
    }
    func leg(_ limb: Limb, root: P, foot: Double) -> (P, P, P) {
        switch limb {
        case let .angles(a, b):
            let k = root + dir(a) * Body.thigh
            let an = k + dir(b) * Body.shin
            return (k, an, an + dir(foot) * Body.foot)
        case let .ik(target, bend):
            let r = solveIK(root: root, target: target, l1: Body.thigh, l2: Body.shin, bend: bend)
            return (r.joint, r.end, r.end + dir(foot) * Body.foot)
        }
    }
    let (eN, wN) = arm(pose.armN, root: shoulder)
    let (eF, wF) = arm(pose.armF, root: shoulder + farOffset)
    let (kN, aN, tN) = leg(pose.legN, root: hip, foot: pose.footN)
    let (kF, aF, tF) = leg(pose.legF, root: hip + farOffset, foot: pose.footF)
    return Skeleton(hip: hip, neck: neck, shoulder: shoulder, head: head, chestControl: chestControl,
                    elbowN: eN, wristN: wN, elbowF: eF, wristF: wF,
                    kneeN: kN, ankleN: aN, toeN: tN, kneeF: kF, ankleF: aF, toeF: tF)
}

// MARK: - Front-view pose (lateral raise, shrug, mountain pose)

struct FrontPose {
    /// Arm angle away from the body, degrees (0 = hanging, 90 = horizontal).
    var abduction: Double = 6
    /// Elbow bend, degrees.
    var elbowBend: Double = 8
    /// Shoulder elevation in pixels.
    var shrug: Double = 0
    /// Chest expansion for breathing, pixels.
    var breath: Double = 0
    var dumbbells: Bool = false

    func interpolated(to o: FrontPose, _ t: Double) -> FrontPose {
        var p = self
        p.abduction = lerp(abduction, o.abduction, t)
        p.elbowBend = lerp(elbowBend, o.elbowBend, t)
        p.shrug = lerp(shrug, o.shrug, t)
        p.breath = lerp(breath, o.breath, t)
        return p
    }
}

enum AnyPose {
    case side(SidePose)
    case front(FrontPose)

    func interpolated(to other: AnyPose, _ t: Double) -> AnyPose {
        switch (self, other) {
        case let (.side(a), .side(b)): .side(a.interpolated(to: b, t))
        case let (.front(a), .front(b)): .front(a.interpolated(to: b, t))
        default: self
        }
    }
}

// MARK: - Animation

struct Keyframe {
    var pose: AnyPose
    /// Frames to hold this pose.
    var hold: Int
    /// Frames to move to the next keyframe (the last one moves back to the first, so videos loop).
    var move: Int
}

enum Prop {
    case floorMat(from: Double, to: Double)
    /// Flat or inclined bench: seat from x0 to x1 at height `top`; optional back pad rising from `backFrom` at `incline` degrees.
    case bench(x0: Double, x1: Double, top: Double, backFrom: Double? = nil, incline: Double = 0, backLength: Double = 0, backFacesLeft: Bool = true)
    case counter(x: Double, width: Double, top: Double)
    case pole(x: Double, top: Double)
    case towel(x: Double)
}

struct Animation {
    var name: String
    var keyframes: [Keyframe]
    var props: [Prop] = []
    /// Scales the scene about the floor centre, to fit tall movements (arms overhead) in the frame.
    var zoom: Double = 1
    var fps: Int = 30

    var frameCount: Int { keyframes.map { $0.hold + $0.move }.reduce(0, +) }

    /// Pose at frame `f`, eased between keyframes.
    func pose(at f: Int) -> AnyPose {
        var frame = f % max(frameCount, 1)
        for (i, k) in keyframes.enumerated() {
            if frame < k.hold { return k.pose }
            frame -= k.hold
            if frame < k.move {
                let next = keyframes[(i + 1) % keyframes.count].pose
                let t = Double(frame) / Double(k.move)
                let eased = (1 - cos(t * .pi)) / 2
                return k.pose.interpolated(to: next, eased)
            }
            frame -= k.move
        }
        return keyframes[0].pose
    }
}
