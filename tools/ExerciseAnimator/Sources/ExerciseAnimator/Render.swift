import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 600

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}

enum Palette {
    static let bgTop = rgb(0xF7F9FB), bgBottom = rgb(0xE4EBF1)
    static let floor = rgb(0xD5DEE7), floorLine = rgb(0xB9C5D1)
    static let shirt = rgb(0x2BA38A), shirtFar = rgb(0x1D7766)
    static let pants = rgb(0x34466B), pantsFar = rgb(0x243250)
    static let skin = rgb(0xE5AE85), skinFar = rgb(0xC48D66)
    static let hair = rgb(0x2B2F38)
    static let shoe = rgb(0x2B2F38), shoeFar = rgb(0x1C1F26)
    static let plate = rgb(0x3B4049), plateRim = rgb(0x5B626E), handle = rgb(0x9097A1)
    static let benchPad = rgb(0x46505F), benchFrame = rgb(0x9AA5B1)
    static let mat = rgb(0xAFC0E6), towel = rgb(0xF0D9A8)
    static let wood = rgb(0xCDB591), woodEdge = rgb(0xAE9670)
    static let shadow = rgb(0x000000, 0.10)
}

// MARK: - Drawing primitives

private func stroke(_ ctx: CGContext, _ a: P, _ b: P, width: Double, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: a.cg)
    ctx.addLine(to: b.cg)
    ctx.strokePath()
}

private func dot(_ ctx: CGContext, _ c: P, _ r: Double, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

private func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: Double, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

private func dumbbell(_ ctx: CGContext, at c: P, style: DumbbellStyle, axis: Double = 90) {
    switch style {
    case .none:
        return
    case .endOn:
        dot(ctx, c, 17, Palette.plateRim)
        dot(ctx, c, 14, Palette.plate)
        dot(ctx, c, 4, Palette.handle)
    case .upright:
        let d = dir(axis)
        stroke(ctx, c - d * 22, c + d * 22, width: 6, color: Palette.handle)
        for end in [c - d * 22, c + d * 22] {
            stroke(ctx, end - dir(axis + 90) * 15, end + dir(axis + 90) * 15, width: 12, color: Palette.plate)
        }
    }
}

// MARK: - Scene

private func background(_ ctx: CGContext) {
    let size = Double(canvas)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [Palette.bgBottom, Palette.bgTop] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])
    ctx.setFillColor(Palette.floor)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: Body.ground))
    stroke(ctx, P(0, Body.ground), P(size, Body.ground), width: 2, color: Palette.floorLine)
}

private func draw(_ prop: Prop, _ ctx: CGContext) {
    let g = Body.ground
    switch prop {
    case let .floorMat(from, to):
        roundedRect(ctx, CGRect(x: from, y: g - 2, width: to - from, height: 10), radius: 5, Palette.mat)
    case let .bench(x0, x1, top, backFrom, incline, backLength, backFacesLeft):
        // Frame legs.
        stroke(ctx, P(x0 + 25, g), P(x0 + 25, top - 10), width: 8, color: Palette.benchFrame)
        stroke(ctx, P(x1 - 25, g), P(x1 - 25, top - 10), width: 8, color: Palette.benchFrame)
        stroke(ctx, P(x0 + 10, g + 2), P(x0 + 45, g + 2), width: 8, color: Palette.benchFrame)
        stroke(ctx, P(x1 - 45, g + 2), P(x1 - 10, g + 2), width: 8, color: Palette.benchFrame)
        roundedRect(ctx, CGRect(x: x0, y: top - 18, width: x1 - x0, height: 18), radius: 7, Palette.benchPad)
        if let backFrom {
            let start = P(backFrom, top - 9)
            let a = backFacesLeft ? 180 - incline : incline
            let end = start + dir(a) * backLength
            stroke(ctx, start, end, width: 18, color: Palette.benchPad)
            stroke(ctx, start + dir(a) * (backLength * 0.6) + P(0, -8), P(start.x + (end.x - start.x) * 0.6, g), width: 7, color: Palette.benchFrame)
        }
    case let .counter(x, width, top):
        ctx.setFillColor(Palette.woodEdge)
        ctx.fill(CGRect(x: x, y: g, width: width, height: top - g))
        roundedRect(ctx, CGRect(x: x - 6, y: top - 14, width: width + 12, height: 16), radius: 4, Palette.wood)
    case let .pole(x, top):
        stroke(ctx, P(x, g), P(x, top), width: 10, color: Palette.benchFrame)
        stroke(ctx, P(x - 30, g + 3), P(x + 30, g + 3), width: 8, color: Palette.benchFrame)
    case let .towel(x):
        roundedRect(ctx, CGRect(x: x - 28, y: g - 1, width: 56, height: 9), radius: 4, Palette.towel)
    }
}

private func drawSide(_ pose: SidePose, _ ctx: CGContext) {
    let s = solve(pose)
    // Contact shadow.
    let lowest = min(s.ankleN.y, s.ankleF.y, s.hip.y, s.wristN.y)
    if lowest < Body.ground + 60 {
        let cx = (s.hip.x + s.ankleN.x + s.neck.x) / 3
        ctx.setFillColor(Palette.shadow)
        ctx.fillEllipse(in: CGRect(x: cx - 130, y: Body.ground - 7, width: 260, height: 14))
    }

    func leg(_ hip: P, _ knee: P, _ ankle: P, _ toe: P, far: Bool) {
        stroke(ctx, hip, knee, width: 31, color: far ? Palette.pantsFar : Palette.pants)
        stroke(ctx, knee, ankle, width: 24, color: far ? Palette.pantsFar : Palette.pants)
        stroke(ctx, ankle, toe, width: 15, color: far ? Palette.shoeFar : Palette.shoe)
    }
    func arm(_ shoulder: P, _ elbow: P, _ wrist: P, far: Bool) {
        let skin = far ? Palette.skinFar : Palette.skin
        stroke(ctx, shoulder, elbow, width: 21, color: skin)
        stroke(ctx, shoulder, shoulder + (elbow - shoulder) * 0.5, width: 26, color: far ? Palette.shirtFar : Palette.shirt)
        stroke(ctx, elbow, wrist, width: 17, color: skin)
        dot(ctx, wrist + (wrist - elbow) * (8 / max((wrist - elbow).length, 1)), 9, skin)
    }

    // Far side first.
    leg(s.hip + farOffset, s.kneeF, s.ankleF, s.toeF, far: true)
    arm(s.shoulder + farOffset, s.elbowF, s.wristF, far: true)
    dumbbell(ctx, at: s.wristF, style: pose.dumbbellF, axis: angle(of: s.wristF - s.elbowF) + 90)

    // Torso: hips (shorts) and a curved shirt from hip to neck.
    dot(ctx, s.hip, 23, Palette.pants)
    ctx.setStrokeColor(Palette.shirt)
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    let shirtStart = s.hip + (s.neck - s.hip) * 0.15
    ctx.move(to: shirtStart.cg)
    ctx.addQuadCurve(to: (s.neck - (s.neck - s.hip) * 0.06).cg, control: s.chestControl.cg)
    ctx.strokePath()
    stroke(ctx, s.neck, s.neck + (s.head - s.neck) * 0.45, width: 15, color: Palette.skin)
    dot(ctx, s.head, Body.headRadius, Palette.skin)
    // Hair over the crown and the back of the head, leaving the face (front) visible.
    let up = s.head - s.neck
    let upUnit = up * (1 / max(up.length, 1))
    let facing = dir(angle(of: up) - 90)
    let crown = s.head + upUnit * 11 - facing * 9
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: s.head.x - Body.headRadius, y: s.head.y - Body.headRadius, width: 2 * Body.headRadius, height: 2 * Body.headRadius))
    ctx.clip()
    dot(ctx, crown, Body.headRadius * 0.86, Palette.hair)
    ctx.restoreGState()
    // Eye, so the facing direction reads.
    dot(ctx, s.head + facing * 15 + upUnit * 3, 2.6, Palette.hair)

    leg(s.hip, s.kneeN, s.ankleN, s.toeN, far: false)
    if pose.sharedDumbbell {
        let mid = (s.wristN + s.wristF) * 0.5 + (s.wristN - s.elbowN) * (10 / max((s.wristN - s.elbowN).length, 1))
        dumbbell(ctx, at: mid, style: .upright, axis: 90)
    }
    arm(s.shoulder, s.elbowN, s.wristN, far: false)
    dumbbell(ctx, at: s.wristN, style: pose.dumbbellN, axis: angle(of: s.wristN - s.elbowN) + 90)
}

private func drawFront(_ pose: FrontPose, _ ctx: CGContext) {
    let cx = 300.0
    let hipY = 268.0
    let shoulderY = hipY + 128 + pose.shrug
    ctx.setFillColor(Palette.shadow)
    ctx.fillEllipse(in: CGRect(x: cx - 90, y: Body.ground - 7, width: 180, height: 14))
    // Legs.
    for side in [-1.0, 1.0] {
        let hip = P(cx + side * 18, hipY)
        let knee = P(cx + side * 21, hipY - Body.thigh)
        let ankle = P(cx + side * 24, Body.ankleY)
        stroke(ctx, hip, knee, width: 31, color: Palette.pants)
        stroke(ctx, knee, ankle, width: 24, color: Palette.pants)
        stroke(ctx, ankle, ankle + P(side * 14, -4), width: 16, color: Palette.shoe)
    }
    roundedRect(ctx, CGRect(x: cx - 34, y: hipY - 22, width: 68, height: 40), radius: 16, Palette.pants)
    // Torso.
    let w = 86 + pose.breath
    roundedRect(ctx, CGRect(x: cx - w / 2, y: hipY - 4, width: w, height: shoulderY - hipY + 22), radius: 26, Palette.shirt)
    // Neck and head.
    stroke(ctx, P(cx, shoulderY + 10), P(cx, shoulderY + 34), width: 16, color: Palette.skin)
    let head = P(cx, shoulderY + 50)
    dot(ctx, head, Body.headRadius, Palette.skin)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: head.x - Body.headRadius, y: head.y - Body.headRadius, width: 2 * Body.headRadius, height: 2 * Body.headRadius))
    ctx.clip()
    ctx.setFillColor(Palette.hair)
    ctx.fill(CGRect(x: head.x - 30, y: head.y + 12, width: 60, height: 30))
    ctx.restoreGState()
    // Arms.
    for side in [-1.0, 1.0] {
        let shoulder = P(cx + side * 40, shoulderY)
        let upperAngle = -90 + side * pose.abduction
        let elbow = shoulder + dir(upperAngle) * Body.upperArm
        let foreAngle = upperAngle + side * pose.elbowBend
        let wrist = elbow + dir(foreAngle) * Body.forearm
        stroke(ctx, shoulder, elbow, width: 21, color: Palette.skin)
        stroke(ctx, shoulder, shoulder + (elbow - shoulder) * 0.5, width: 26, color: Palette.shirt)
        stroke(ctx, elbow, wrist, width: 17, color: Palette.skin)
        dot(ctx, wrist + dir(foreAngle) * 8, 9, Palette.skin)
        if pose.dumbbells { dumbbell(ctx, at: wrist + dir(foreAngle) * 8, style: .endOn) }
    }
}

func renderFrame(_ animation: Animation, frame: Int, into ctx: CGContext) {
    background(ctx)
    ctx.saveGState()
    if animation.zoom != 1 {
        ctx.translateBy(x: 300, y: Body.ground)
        ctx.scaleBy(x: animation.zoom, y: animation.zoom)
        ctx.translateBy(x: -300, y: -Body.ground)
    }
    for prop in animation.props { draw(prop, ctx) }
    switch animation.pose(at: frame) {
    case .side(let p): drawSide(p, ctx)
    case .front(let p): drawFront(p, ctx)
    }
    ctx.restoreGState()
}

// MARK: - Output

func makeContext(data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    CGContext(data: data, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// Writes a looping H.264 MP4.
func writeVideo(_ animation: Animation, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: canvas,
        AVVideoHeightKey: canvas,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 700_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: animation.fps * 2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: canvas,
        kCVPixelBufferHeightKey as String: canvas,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<animation.frameCount {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
        guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = makeContext(data: CVPixelBufferGetBaseAddress(buffer), bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
        renderFrame(animation, frame: frame, into: ctx)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(animation.fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}

/// A strip of evenly spaced frames, for reviewing poses without playing the video.
func writeContactSheet(_ animation: Animation, frames: Int = 5, to url: URL) throws {
    let scale = 0.5
    let tile = Int(Double(canvas) * scale)
    let sheet = CGContext(data: nil, width: tile * frames, height: tile, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    for i in 0..<frames {
        let ctx = makeContext()
        renderFrame(animation, frame: animation.frameCount * i / frames, into: ctx)
        sheet.draw(ctx.makeImage()!, in: CGRect(x: tile * i, y: 0, width: tile, height: tile))
    }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, sheet.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}
