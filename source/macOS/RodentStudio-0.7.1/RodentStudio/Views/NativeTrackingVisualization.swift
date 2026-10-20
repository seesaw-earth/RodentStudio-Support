import SwiftUI
import AppKit

/// Colors and connectivity copied from RodentPose 1.0 DesignSystem/Keypoints.swift
/// and RodentLimb 1.1.2 DesignSystem/PoseTypes.swift, respectively.
/// Crucially these are NOT one shared pseudo-skeleton.
enum NativeTrackingAppearance {
    static let poseColors: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]
    // lf, lh, rf, rh, tail, nose, mouth (DLC model output order).
    static let limbColors: [Color] = [
        Color(red:30/255,green:127/255,blue:216/255),
        Color(red:18/255,green:160/255,blue:90/255),
        Color(red:229/255,green:64/255,blue:79/255),
        Color(red:138/255,green:79/255,blue:224/255),
        Color(red:229/255,green:143/255,blue:166/255),
        Color(red:242/255,green:165/255,blue:0/255),
        Color(red:95/255,green:195/255,blue:232/255)
    ]
    static let poseBones = [(0,1),(0,2),(1,3),(2,3),(3,4),(4,5)]
    static let limbBones = [(0,2),(1,3),(5,6),(0,1),(2,3),(1,4),(3,4)]
    static func color(_ model: PoseModelKind, at index: Int) -> Color {
        let colors = model == .mousePose ? poseColors : limbColors
        return colors[abs(index) % colors.count]
    }
    static func bones(_ model: PoseModelKind) -> [(Int,Int)] {
        model == .mousePose ? poseBones : limbBones
    }
    static func trailIndex(_ model: PoseModelKind) -> Int { 4 } // Pose body centre; Limb tail base
}

/// The coordinate system of stored tracking points is the upright/displayed video frame.
/// Draw both the image and all annotations in the *same aspect-fit rectangle*.
struct NativeTrackingCanvas: View {
    let model: PoseModelKind
    let image: NSImage
    let videoWidth: Int
    let videoHeight: Int
    let frame: NativeTrackedFrame
    let previous: [NativeTrackedFrame]
    let threshold: Double
    var showTrail: Bool = true
    var trailSeconds: Double = 2

    var body: some View {
        GeometryReader { geo in
            let imageSize = CGSize(width:max(1,image.size.width),height:max(1,image.size.height))
            let fit = Self.fitRect(imageSize, inside:geo.size)
            let aspectError = abs(imageSize.width / imageSize.height - CGFloat(max(videoWidth,1)) / CGFloat(max(videoHeight,1)))
            ZStack(alignment:.topLeading) {
                Color.black
                Image(nsImage:image).resizable().interpolation(.high)
                    .frame(width:fit.width,height:fit.height)
                    .position(x:fit.midX,y:fit.midY)
                if aspectError < 0.015 {
                    Canvas { ctx, _ in
                        draw(&ctx, frame:frame, earlier:previous, in:fit)
                    }.allowsHitTesting(false)
                } else {
                    Text(L("Orientation mismatch: overlay suppressed", "视频方向不匹配：已停止绘制标点"))
                        .font(.caption).foregroundStyle(.white)
                        .padding(7).background(.red.opacity(0.8),in:RoundedRectangle(cornerRadius:6))
                        .padding(9)
                }
            }
        }
        .accessibilityLabel(L("Aligned tracking preview", "已对齐的姿态视频预览"))
    }

    static func fitRect(_ image: CGSize, inside size: CGSize) -> CGRect {
        let s = min(size.width / max(image.width,1),size.height / max(image.height,1))
        let w = image.width * s, h = image.height * s
        return CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h)
    }

    private func draw(_ ctx: inout GraphicsContext, frame:NativeTrackedFrame,
                      earlier:[NativeTrackedFrame],in rect:CGRect) {
        func location(_ pt:NativeTrackPoint) -> CGPoint {
            CGPoint(x:rect.minX + CGFloat(pt.x / Double(max(videoWidth,1))) * rect.width,
                    y:rect.minY + CGFloat(pt.y / Double(max(videoHeight,1))) * rect.height)
        }
        func good(_ p:NativeTrackPoint) -> Bool {
            p.x.isFinite && p.y.isFinite && p.x >= 0 && p.y >= 0 && p.confidence >= threshold
        }
        if showTrail {
            let key = NativeTrackingAppearance.trailIndex(model)
            let eligible = earlier.filter { $0.time >= frame.time - max(0.1,trailSeconds) && $0.time <= frame.time }
            var path = Path()
            var hadPoint = false
            var oldTime:Double? = nil
            for item in eligible {
                guard item.points.indices.contains(key), !item.inferenceFailed, item.score > 0,
                      good(item.points[key]) else { hadPoint = false; oldTime = nil; continue }
                let pos = location(item.points[key])
                if hadPoint, let previousTime=oldTime,
                   item.time - previousTime < max(0.10,2.5/max(frameRate(earlier),1)) {
                    path.addLine(to:pos)
                } else { path.move(to:pos) }
                hadPoint = true
                oldTime = item.time
            }
            let color:Color = model == .mousePose ? .orange : .pink
            ctx.stroke(path,with:.color(.black.opacity(0.65)),style:StrokeStyle(lineWidth:4,lineCap:.round,lineJoin:.round))
            ctx.stroke(path,with:.color(color.opacity(0.85)),style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round))
        }
        for (a,b) in NativeTrackingAppearance.bones(model) {
            guard frame.points.indices.contains(a),frame.points.indices.contains(b),
                  good(frame.points[a]),good(frame.points[b]) else {continue}
            let p = location(frame.points[a]), q = location(frame.points[b])
            var path = Path();path.move(to:p);path.addLine(to:q)
            ctx.stroke(path,with:.color(.black.opacity(0.5)),lineWidth:4)
            ctx.stroke(path,with:.color(.white.opacity(0.94)),lineWidth:2)
        }
        for (n,p) in frame.points.enumerated() {
            guard good(p) else {continue}
            let q = location(p)
            let radius:CGFloat = 4.2
            let circle=Path(ellipseIn:CGRect(x:q.x-radius,y:q.y-radius,width:radius*2,height:radius*2))
            ctx.fill(circle,with:.color(NativeTrackingAppearance.color(model,at:n)))
            ctx.stroke(circle,with:.color(.white),lineWidth:1.1)
        }
    }
    /// Used only to detect implausible jumps when drawing connecting trail segments.
    private func frameRate(_ frames:[NativeTrackedFrame]) -> Double {
        guard frames.count > 1 else {return 30}
        let elapsed = frames.last!.time - frames.first!.time
        return elapsed > 0 ? Double(frames.count-1)/elapsed : 30
    }
}

struct NativeLiveTrackingPreviewView: View {
    let snapshot: NativeLivePreview
    var body: some View {
        let frame = NativeTrackedFrame(index:0,time:snapshot.presentationTime,score:1,points:snapshot.points)
        NativeTrackingCanvas(model:snapshot.model,image:snapshot.image,
                             videoWidth:snapshot.frameWidth,videoHeight:snapshot.frameHeight,
                             frame:frame,previous:[frame],threshold:0.3,showTrail:false)
            .frame(height: min(360, max(175,CGFloat(snapshot.frameHeight)*0.45)))
            .clipShape(RoundedRectangle(cornerRadius:8))
    }
}
