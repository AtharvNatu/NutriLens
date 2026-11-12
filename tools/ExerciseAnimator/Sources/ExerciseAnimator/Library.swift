import Foundation

// Keyframes for every movement in the plan. Coordinates are pixels on a 600 × 600 canvas,
// y up, floor at y = 70, ankles at y = 80. The figure faces right unless lying down.

private let standAnkleN = P(300, 80)
private let standAnkleF = P(306, 80)

private func standingLegs(_ pose: inout SidePose, ankleN: P = standAnkleN, ankleF: P = standAnkleF) {
    pose.legN = .ik(ankleN, bend: 1)
    pose.legF = .ik(ankleF, bend: 1)
}

private func side(_ pose: SidePose, hold: Int, move: Int) -> Keyframe {
    Keyframe(pose: .side(pose), hold: hold, move: move)
}

private func front(_ pose: FrontPose, hold: Int, move: Int) -> Keyframe {
    Keyframe(pose: .front(pose), hold: hold, move: move)
}

private func standing(hip: P = P(292, 288), torso: Double = 89) -> SidePose {
    var p = SidePose(anchor: .hip(hip), torso: torso)
    standingLegs(&p)
    return p
}

// MARK: - Strength

private var gobletSquat: Animation {
    var top = standing(hip: P(292, 288), torso: 88)
    top.armN = .ik(P(338, 392), bend: -1)
    top.armF = .ik(P(332, 392), bend: -1)
    top.sharedDumbbell = true
    var bottom = top
    bottom.anchor = .hip(P(232, 180))
    bottom.torso = 58
    bottom.head = 22
    bottom.armN = .ik(P(345, 264), bend: -1)
    bottom.armF = .ik(P(339, 264), bend: -1)
    return Animation(name: "ex01-goblet-squat", keyframes: [
        side(top, hold: 12, move: 36), side(bottom, hold: 6, move: 30),
    ])
}

private var benchPress: Animation {
    var top = SidePose(anchor: .hip(P(360, 170)), torso: 180)
    top.legN = .ik(P(455, 80), bend: 1)
    top.legF = .ik(P(448, 80), bend: 1)
    top.armN = .ik(P(232, 318), bend: -1)
    top.armF = .ik(P(226, 318), bend: -1)
    top.dumbbellN = .endOn
    top.dumbbellF = .endOn
    var bottom = top
    bottom.armN = .ik(P(238, 214), bend: -1)
    bottom.armF = .ik(P(232, 214), bend: -1)
    return Animation(name: "ex02-bench-press", keyframes: [
        side(top, hold: 10, move: 36), side(bottom, hold: 4, move: 26),
    ], props: [.bench(x0: 140, x1: 420, top: 150)])
}

private func hingedSupport(hip: P = P(240, 262), torso: Double = 18) -> SidePose {
    var p = SidePose(anchor: .hip(hip), torso: torso, head: -8)
    p.legN = .ik(P(175, 80), bend: 1)
    p.legF = .ik(P(300, 80), bend: 1)
    p.armF = .ik(P(432, 198), bend: -1)
    return p
}

private var oneArmRow: Animation {
    var down = hingedSupport()
    down.armN = .ik(P(372, 152), bend: 1)
    down.dumbbellN = .endOn
    var up = down
    up.armN = .ik(P(338, 252), bend: 1)
    return Animation(name: "ex03-one-arm-row", keyframes: [
        side(down, hold: 8, move: 24), side(up, hold: 8, move: 30),
    ], props: [.bench(x0: 405, x1: 545, top: 190)])
}

private var romanianDeadlift: Animation {
    var top = standing(hip: P(295, 288), torso: 88)
    top.armN = .angles(-88, -88)
    top.armF = .angles(-88, -88)
    top.dumbbellN = .endOn
    top.dumbbellF = .endOn
    var bottom = top
    bottom.anchor = .hip(P(240, 272))
    bottom.torso = 22
    bottom.head = 10
    bottom.armN = .angles(-92, -92)
    bottom.armF = .angles(-92, -92)
    return Animation(name: "ex04-romanian-deadlift", keyframes: [
        side(top, hold: 10, move: 40), side(bottom, hold: 6, move: 30),
    ])
}

private var deadBug: Animation {
    var start = SidePose(anchor: .hip(P(340, 98)), torso: 180)
    start.armN = .angles(90, 90)
    start.armF = .angles(92, 92)
    start.legN = .angles(90, 0)
    start.legF = .angles(92, 2)
    start.footN = 80
    start.footF = 80
    var nearArmFarLeg = start
    nearArmFarLeg.armN = .angles(165, 168)
    nearArmFarLeg.legF = .angles(12, 8)
    nearArmFarLeg.footF = 40
    var farArmNearLeg = start
    farArmNearLeg.armF = .angles(165, 168)
    farArmNearLeg.legN = .angles(12, 8)
    farArmNearLeg.footN = 40
    return Animation(name: "ex05-dead-bug", keyframes: [
        side(start, hold: 8, move: 30), side(nearArmFarLeg, hold: 10, move: 30),
        side(start, hold: 8, move: 30), side(farArmNearLeg, hold: 10, move: 30),
    ], props: [.floorMat(from: 40, to: 560)])
}

private var calfRaise: Animation {
    var down = standing()
    down.armN = .ik(P(430, 254), bend: -1)
    var up = down
    up.anchor = .hip(P(298, 312))
    standingLegs(&up, ankleN: P(306, 104), ankleF: P(312, 104))
    up.footN = -34
    up.footF = -34
    up.armN = .ik(P(430, 258), bend: -1)
    return Animation(name: "ex06-calf-raise", keyframes: [
        side(down, hold: 8, move: 18), side(up, hold: 14, move: 30),
    ], props: [.counter(x: 420, width: 150, top: 250)])
}

private var splitSquat: Animation {
    var top = SidePose(anchor: .hip(P(268, 262)), torso: 88)
    top.legN = .ik(P(330, 80), bend: 1)
    top.legF = .ik(P(170, 98), bend: 1)
    top.footF = -36
    top.armF = .ik(P(372, 300), bend: -1)
    top.armN = .angles(-92, -92)
    var bottom = top
    bottom.anchor = .hip(P(258, 180))
    bottom.torso = 86
    bottom.armF = .ik(P(372, 228), bend: -1)
    return Animation(name: "ex07-split-squat", keyframes: [
        side(top, hold: 8, move: 32), side(bottom, hold: 4, move: 26),
    ], props: [.pole(x: 380, top: 330)])
}

private var inclinePushUp: Animation {
    func plank(_ theta: Double) -> SidePose {
        var p = SidePose(anchor: .ankle(P(150, 96)), torso: theta)
        p.legN = .angles(theta + 180, theta + 180)
        p.legF = .angles(theta + 180, theta + 180)
        p.footN = -55
        p.footF = -55
        p.armN = .ik(P(452, 180), bend: -1)
        p.armF = .ik(P(446, 180), bend: -1)
        return p
    }
    return Animation(name: "ex08-incline-push-up", keyframes: [
        side(plank(42), hold: 8, move: 30), side(plank(31), hold: 4, move: 24),
    ], props: [.counter(x: 440, width: 120, top: 172)])
}

private var gluteBridge: Animation {
    var down = SidePose(anchor: .neck(P(175, 98)), torso: 180)
    down.legN = .ik(P(430, 80), bend: 1)
    down.legF = .ik(P(424, 80), bend: 1)
    down.armN = .angles(-4, -2)
    down.armF = .angles(-6, -3)
    var up = down
    up.torso = 205
    up.head = -25
    return Animation(name: "ex09-glute-bridge", keyframes: [
        side(down, hold: 10, move: 26), side(up, hold: 14, move: 30),
    ], props: [.floorMat(from: 60, to: 540)])
}

private var shoulderPress: Animation {
    var bottom = SidePose(anchor: .hip(P(285, 172)), torso: 90)
    bottom.legN = .ik(P(400, 80), bend: 1)
    bottom.legF = .ik(P(394, 80), bend: 1)
    bottom.armN = .ik(P(320, 318), bend: -1)
    bottom.armF = .ik(P(314, 318), bend: -1)
    bottom.dumbbellN = .endOn
    bottom.dumbbellF = .endOn
    var top = bottom
    top.armN = .ik(P(292, 460), bend: -1)
    top.armF = .ik(P(286, 460), bend: -1)
    return Animation(name: "ex10-shoulder-press", keyframes: [
        side(bottom, hold: 8, move: 24), side(top, hold: 4, move: 36),
    ], props: [.bench(x0: 230, x1: 360, top: 150, backFrom: 242, incline: 85, backLength: 230)])
}

private var sidePlank: Animation {
    // Shown from the front: forearm under the shoulder, body in a line to the feet.
    // (The plan starts with the bent-knee version; the app's text says so.)
    func pose(hip: P, torso: Double) -> SidePose {
        var p = SidePose(anchor: .hip(hip), torso: torso, head: 8)
        p.armN = .angles(-90, 180)
        p.armF = .angles(-15, -25)
        p.legN = .ik(P(505, 80), bend: 1)
        p.legF = .ik(P(499, 84), bend: 1)
        p.footN = 80
        p.footF = 80
        return p
    }
    let down = pose(hip: P(316, 98), torso: 152)
    let up = pose(hip: P(321, 132), torso: 165.6)
    return Animation(name: "ex11-side-plank", keyframes: [
        side(down, hold: 8, move: 24), side(up, hold: 40, move: 24),
    ], props: [.floorMat(from: 60, to: 560)])
}

private func curl(name: String, style: DumbbellStyle) -> Animation {
    var rest = standing()
    rest.armN = .angles(-93, -88)
    rest.armF = .angles(-93, -88)
    rest.dumbbellN = style
    rest.dumbbellF = style
    var near = rest
    near.armN = .angles(-95, 72)
    var far = rest
    far.armF = .angles(-95, 72)
    return Animation(name: name, keyframes: [
        side(rest, hold: 6, move: 24), side(near, hold: 4, move: 30),
        side(rest, hold: 6, move: 24), side(far, hold: 4, move: 30),
    ])
}

private var inclinePress: Animation {
    var bottom = SidePose(anchor: .hip(P(350, 170)), torso: 155)
    bottom.legN = .ik(P(455, 80), bend: 1)
    bottom.legF = .ik(P(448, 80), bend: 1)
    bottom.armN = .ik(P(242, 255), bend: -1)
    bottom.armF = .ik(P(236, 255), bend: -1)
    bottom.dumbbellN = .endOn
    bottom.dumbbellF = .endOn
    var top = bottom
    top.armN = .ik(P(290, 362), bend: -1)
    top.armF = .ik(P(284, 362), bend: -1)
    return Animation(name: "ex13-incline-press", keyframes: [
        side(top, hold: 10, move: 36), side(bottom, hold: 4, move: 26),
    ], props: [.bench(x0: 300, x1: 430, top: 150, backFrom: 312, incline: 25, backLength: 190)])
}

private var lateralRaise: Animation {
    let down = FrontPose(abduction: 8, elbowBend: 10, dumbbells: true)
    let up = FrontPose(abduction: 82, elbowBend: 12, dumbbells: true)
    return Animation(name: "ex14-lateral-raise", keyframes: [
        front(down, hold: 8, move: 26), front(up, hold: 6, move: 36),
    ])
}

private func chestSupported(name: String, top: SidePose, hold: Int) -> Animation {
    var hang = top
    hang.armN = .ik(P(378, 98), bend: 1)
    hang.armF = .ik(P(372, 98), bend: 1)
    hang.armScale = 1
    return Animation(name: name, keyframes: [
        side(hang, hold: 8, move: 24), side(top, hold: hold, move: 30),
    ], props: [.bench(x0: 215, x1: 300, top: 140, backFrom: 280, incline: 35, backLength: 200, backFacesLeft: false)])
}

private func pronePose() -> SidePose {
    var p = SidePose(anchor: .hip(P(262, 146)), torso: 35, head: -10)
    p.legN = .ik(P(140, 80), bend: 1)
    p.legF = .ik(P(146, 80), bend: 1)
    p.dumbbellN = .endOn
    p.dumbbellF = .endOn
    return p
}

private var chestSupportedRow: Animation {
    var top = pronePose()
    top.armN = .ik(P(330, 186), bend: 1)
    top.armF = .ik(P(324, 186), bend: 1)
    return chestSupported(name: "ex15-chest-supported-row", top: top, hold: 8)
}

private var reverseFly: Animation {
    var top = pronePose()
    top.armN = .angles(-62, -55)
    top.armF = .angles(-60, -53)
    top.armScale = 0.32
    var hang = top
    hang.armN = .angles(-88, -90)
    hang.armF = .angles(-88, -90)
    hang.armScale = 1
    return Animation(name: "ex16-reverse-fly", keyframes: [
        side(hang, hold: 8, move: 26), side(top, hold: 6, move: 32),
    ], props: [.bench(x0: 215, x1: 300, top: 140, backFrom: 280, incline: 35, backLength: 200, backFacesLeft: false)])
}

private var shrug: Animation {
    let down = FrontPose(abduction: 4, elbowBend: 0, dumbbells: true)
    var up = down
    up.shrug = 24
    return Animation(name: "ex17-shrug", keyframes: [
        front(down, hold: 8, move: 18), front(up, hold: 14, move: 24),
    ])
}

private var overheadExtension: Animation {
    var top = standing()
    top.armN = .angles(96, 92)
    top.armF = .angles(98, 94)
    top.sharedDumbbell = true
    var bottom = top
    bottom.armN = .angles(100, 232)
    bottom.armF = .angles(102, 234)
    return Animation(name: "ex19-overhead-extension", keyframes: [
        side(top, hold: 8, move: 30), side(bottom, hold: 4, move: 24),
    ], zoom: 0.84)
}

private var kickback: Animation {
    var bent = hingedSupport()
    bent.armN = .angles(196, -90)
    bent.dumbbellN = .upright
    var straight = bent
    straight.armN = .angles(196, 194)
    return Animation(name: "ex20-triceps-kickback", keyframes: [
        side(bent, hold: 6, move: 22), side(straight, hold: 8, move: 30),
    ], props: [.bench(x0: 405, x1: 545, top: 190)])
}

// MARK: - Yoga

private var mountainPose: Animation {
    let exhale = FrontPose(abduction: 6, elbowBend: 4)
    var inhale = exhale
    inhale.breath = 7
    inhale.shrug = 3
    return Animation(name: "y1-mountain-pose", keyframes: [
        front(exhale, hold: 20, move: 50), front(inhale, hold: 12, move: 50),
    ])
}

private func allFours(curve: Double = 0, head: Double = -10) -> SidePose {
    var p = SidePose(anchor: .hip(P(232, 186)), torso: 17, torsoCurve: curve, head: head)
    p.legN = .angles(-90, 180)
    p.legF = .angles(-90, 180)
    p.footN = 180
    p.footF = 180
    p.armN = .angles(-90, -90)
    p.armF = .angles(-90, -90)
    return p
}

private var catCow: Animation {
    Animation(name: "y2-cat-cow", keyframes: [
        side(allFours(curve: 26, head: -45), hold: 10, move: 45),
        side(allFours(curve: -20, head: 22), hold: 10, move: 45),
    ], props: [.floorMat(from: 40, to: 560)])
}

private var childPose: Animation {
    var child = SidePose(anchor: .hip(P(150, 132)), torso: -6, head: 2)
    child.legN = .angles(-31, 180)
    child.legF = .angles(-31, 180)
    child.footN = 180
    child.footF = 180
    child.armN = .angles(-7, -2)
    child.armF = .angles(-7, -2)
    return Animation(name: "y3-child-pose", keyframes: [
        side(allFours(), hold: 12, move: 45), side(child, hold: 45, move: 45),
    ], props: [.floorMat(from: 40, to: 560)])
}

private var lowLunge: Animation {
    func pose(hip: P, rearThigh: Double, torso: Double) -> SidePose {
        var p = SidePose(anchor: .hip(hip), torso: torso)
        p.legN = .ik(P(392, 80), bend: 1)
        p.legF = .angles(rearThigh, 182)
        p.footF = 180
        p.armN = .ik(P(352, 196), bend: -1)
        p.armF = .ik(P(346, 196), bend: -1)
        return p
    }
    return Animation(name: "y4-low-lunge", keyframes: [
        side(pose(hip: P(280, 180), rearThigh: -128.6, torso: 88), hold: 12, move: 50),
        side(pose(hip: P(304, 172), rearThigh: -139, torso: 92), hold: 30, move: 50),
    ], props: [.towel(x: 210)])
}

private var savasana: Animation {
    var rest = SidePose(anchor: .hip(P(330, 96)), torso: 180)
    rest.legN = .angles(-3, -1)
    rest.legF = .angles(-2, 0)
    rest.footN = 70
    rest.footF = 74
    rest.armN = .angles(-6, -3)
    rest.armF = .angles(-4, -2)
    var breathIn = rest
    breathIn.torsoCurve = -5
    return Animation(name: "y5-savasana", keyframes: [
        side(rest, hold: 30, move: 60), side(breathIn, hold: 20, move: 60),
    ], props: [.floorMat(from: 20, to: 580)])
}

// MARK: - Cardio

private var walking: Animation {
    func contact(frontNear: Bool) -> SidePose {
        var p = SidePose(anchor: .hip(P(296, 280)), torso: 87)
        let front: Limb = .angles(-70, -95)
        let back: Limb = .angles(-112, -125)
        p.legN = frontNear ? front : back
        p.legF = frontNear ? back : front
        p.footN = frontNear ? 12 : -30
        p.footF = frontNear ? -30 : 12
        p.armN = frontNear ? .angles(-112, -100) : .angles(-68, -50)
        p.armF = frontNear ? .angles(-68, -50) : .angles(-112, -100)
        return p
    }
    func passing(supportNear: Bool) -> SidePose {
        var p = SidePose(anchor: .hip(P(296, 287)), torso: 88)
        let support: Limb = .angles(-90, -90)
        let swing: Limb = .angles(-80, -122)
        p.legN = supportNear ? support : swing
        p.legF = supportNear ? swing : support
        p.footN = supportNear ? 0 : -10
        p.footF = supportNear ? -10 : 0
        p.armN = .angles(-90, -80)
        p.armF = .angles(-90, -80)
        return p
    }
    return Animation(name: "c1-walking", keyframes: [
        side(contact(frontNear: true), hold: 0, move: 9), side(passing(supportNear: true), hold: 0, move: 9),
        side(contact(frontNear: false), hold: 0, move: 9), side(passing(supportNear: false), hold: 0, move: 9),
    ])
}

private var jogInPlace: Animation {
    func step(liftNear: Bool, y: Double) -> SidePose {
        var p = SidePose(anchor: .hip(P(296, y)), torso: 86)
        let lifted: Limb = .angles(-58, -112)
        let support: Limb = .angles(-90, -91)
        p.legN = liftNear ? lifted : support
        p.legF = liftNear ? support : lifted
        p.footN = liftNear ? -20 : 0
        p.footF = liftNear ? 0 : -20
        p.armN = liftNear ? .angles(-115, -25) : .angles(-68, 28)
        p.armF = liftNear ? .angles(-68, 28) : .angles(-115, -25)
        return p
    }
    return Animation(name: "c2-jog-in-place", keyframes: [
        side(step(liftNear: true, y: 292), hold: 0, move: 7), side(step(liftNear: true, y: 296), hold: 0, move: 7),
        side(step(liftNear: false, y: 292), hold: 0, move: 7), side(step(liftNear: false, y: 296), hold: 0, move: 7),
    ])
}

let allAnimations: [Animation] = [
    gobletSquat, benchPress, oneArmRow, romanianDeadlift, deadBug, calfRaise, splitSquat, inclinePushUp,
    gluteBridge, shoulderPress, sidePlank, curl(name: "ex12-dumbbell-curl", style: .endOn), inclinePress,
    lateralRaise, chestSupportedRow, reverseFly, shrug, curl(name: "ex18-hammer-curl", style: .upright),
    overheadExtension, kickback,
    mountainPose, catCow, childPose, lowLunge, savasana,
    walking, jogInPlace,
]
