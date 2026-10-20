import Foundation
import AVFoundation
import CoreImage
import CoreGraphics
import CoreVideo
import AppKit

/// Optional MP4 export; never re-runs a pose model. Reader/encoder use one video frame at a time.
/// Tracking coordinates are in the upright image. Unknown timestamp matches are left unannotated.
enum AnnotatedVideoExporter {
    struct Estimate {
        let seconds: Double
        let totalFrames: Int
        let sampleFrames: Int
        let measuredSeconds: Double
        let dimensions: CGSize
    }
    enum ExportError: LocalizedError {
        case missingTrack, noSamples, cannotCreatePool, failed(String)
        var errorDescription: String? {
            switch self {
            case .missingTrack:return "The source movie contains no video track."
            case .noSamples:return "No decodable frames in the selected range."
            case .cannotCreatePool:return "Cannot allocate the output video pixel buffers."
            case .failed(let reason):return reason
            }
        }
    }
    struct Source {
        let url:URL
        let model:PoseModelKind
        let short:NativeTrackingResult?
        let long:LongVideoManifest?
        let directory:URL?
        let firstFrame:Int
        let lastFrame:Int
    }
    private static let ciContext = CIContext(options:[.cacheIntermediates:false])
    private static let mp4Bitrate = 4_000_000

    /// Benchmarks decode, overlay and H.264 encode on a *small real sample* first.
    static func estimate(_ source:Source) throws -> Estimate {
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".mp4")
        defer {try? FileManager.default.removeItem(at:temp)}
        let start=ProcessInfo.processInfo.systemUptime
        let count=try render(source,to:temp,limit:30,progress:nil)
        guard count>0 else{throw ExportError.noSamples}
        let measured=max(0.1,ProcessInfo.processInfo.systemUptime-start)
        let t=AVURLAsset(url:source.url).tracks(withMediaType:.video).first
        let fps=max(1,source.short?.fps ?? Double(t?.nominalFrameRate ?? 30))
        let total=max(1,source.lastFrame-source.firstFrame+1)
        let estimated=measured*Double(total)/Double(count)
        let video=AVURLAsset(url:source.url)
        let t2=video.tracks(withMediaType:.video).first
        let rect=t2.map{CGRect(origin:.zero,size:$0.naturalSize).applying($0.preferredTransform).standardized}
        return Estimate(seconds:estimated,totalFrames:total,sampleFrames:count,measuredSeconds:measured,
                        dimensions:rect?.size ?? .zero)
    }

    @discardableResult static func export(_ source:Source,to destination:URL,
                                         progress:((Double)->Void)? = nil) throws -> Int {
        try render(source,to:destination,limit:nil,progress:progress)
    }

    private static func render(_ source:Source,to destination:URL,limit:Int?,
                               progress:((Double)->Void)?) throws -> Int {
        try? FileManager.default.removeItem(at:destination)
        let asset=AVURLAsset(url:source.url)
        guard let video=asset.tracks(withMediaType:.video).first else{throw ExportError.missingTrack}
        let display=CGRect(origin:.zero,size:video.naturalSize).applying(video.preferredTransform).standardized
        let w=max(2,Int(display.width).quotientAndRemainder(dividingBy:2).quotient*2)
        let h=max(2,Int(display.height).quotientAndRemainder(dividingBy:2).quotient*2)
        let hz=max(1.0,Double(video.nominalFrameRate))
        let a=Double(source.firstFrame)/hz
        let b=Double(source.lastFrame+1)/hz
        let reader=try AVAssetReader(asset:asset)
        reader.timeRange=CMTimeRange(start:CMTime(seconds:a,preferredTimescale:60_000),
                                     duration:CMTime(seconds:max(1/hz,b-a),preferredTimescale:60_000))
        let output=AVAssetReaderTrackOutput(track:video,outputSettings:[
            kCVPixelBufferPixelFormatTypeKey as String:Int(kCVPixelFormatType_32BGRA)
        ])
        output.alwaysCopiesSampleData=false
        guard reader.canAdd(output) else{throw ExportError.failed("Video decoder rejected output settings")}
        reader.add(output)
        let writer=try AVAssetWriter(outputURL:destination,fileType:.mp4)
        let input=AVAssetWriterInput(mediaType:.video,outputSettings:[
            AVVideoCodecKey:AVVideoCodecType.h264,
            AVVideoWidthKey:w,AVVideoHeightKey:h,
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:mp4Bitrate]
        ])
        input.expectsMediaDataInRealTime=false
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        guard writer.canAdd(input) else{throw ExportError.failed("Video encoder rejected input settings")}
        writer.add(input)
        guard writer.startWriting() && reader.startReading() else{
            throw ExportError.failed(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Cannot start video processing")
        }
        writer.startSession(atSourceTime:.zero)
        let upright=video.preferredTransform.concatenating(CGAffineTransform(translationX:-display.minX,y:-display.minY))
        let locator=SavedPoseLocator(source:source)
        var count=0
        var firstPresentationTime: CMTime? = nil
        while let sample=output.copyNextSampleBuffer() {
            if Thread.current.isCancelled {reader.cancelReading();writer.cancelWriting();throw CancellationError()}
            guard let src=CMSampleBufferGetImageBuffer(sample) else{continue}
            guard let pool=adaptor.pixelBufferPool else{throw ExportError.cannotCreatePool}
            var maybe:CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,pool,&maybe)==kCVReturnSuccess,
                  let target=maybe else {throw ExportError.cannotCreatePool}
            let framePTS=CMSampleBufferGetPresentationTimeStamp(sample)
            if firstPresentationTime == nil {firstPresentationTime=framePTS}
            let absolute=CMTimeGetSeconds(framePTS)
            let aligned=CIImage(cvPixelBuffer:src).transformed(by:upright)
            ciContext.render(aligned,to:target,bounds:CGRect(x:0,y:0,width:w,height:h),colorSpace:CGColorSpaceCreateDeviceRGB())
            if let sample=locator.frame(at:absolute,tolerance:0.54/hz) {
                draw(sample.frame,on:target,model:source.model,width:w,height:h,
                     sourceWidth:sample.width,sourceHeight:sample.height)
            }
            var patience=0
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {throw ExportError.failed(writer.error?.localizedDescription ?? "Encoder failed")}
                Thread.sleep(forTimeInterval:0.008)
                patience+=1
                if patience>7_500 {throw ExportError.failed("Encoder stalled for more than one minute")}
            }
            let outputPTS=CMTimeSubtract(framePTS,firstPresentationTime ?? framePTS)
            if !adaptor.append(target,withPresentationTime:outputPTS) {
                throw ExportError.failed(writer.error?.localizedDescription ?? "MP4 frame append failed")
            }
            count+=1
            if count%15==0 {progress?(min(1,Double(count)/Double(max(1,source.lastFrame-source.firstFrame+1))))}
            if let limit,count>=limit {break}
        }
        guard count>0 else {reader.cancelReading();writer.cancelWriting();throw ExportError.noSamples}
        input.markAsFinished()
        reader.cancelReading() // release decoder buffers; finished samples were already passed to the encoder
        let semaphore=DispatchSemaphore(value:0)
        writer.finishWriting {semaphore.signal()}
        guard semaphore.wait(timeout:.now()+180) == .success,writer.status == .completed else {
            throw ExportError.failed(writer.error?.localizedDescription ?? "MP4 writer did not finish")
        }
        progress?(1)
        return count
    }

    private static func draw(_ frame:NativeTrackedFrame,on buffer:CVPixelBuffer,model:PoseModelKind,
                             width:Int,height:Int,sourceWidth:Int,sourceHeight:Int) {
        CVPixelBufferLockBaseAddress(buffer,[])
        defer {CVPixelBufferUnlockBaseAddress(buffer,[])}
        guard let data=CVPixelBufferGetBaseAddress(buffer),
              let ctx=CGContext(data:data,width:width,height:height,bitsPerComponent:8,
                                bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else{return}
        // Display coordinates are top-left origin, after AVAssetTrack.preferredTransform.
        ctx.translateBy(x:0,y:CGFloat(height));ctx.scaleBy(x:1,y:-1)
        let sx=CGFloat(width)/CGFloat(max(sourceWidth,1)),sy=CGFloat(height)/CGFloat(max(sourceHeight,1))
        func valid(_ i:Int)->Bool {frame.points.indices.contains(i) && frame.points[i].x>=0 && frame.points[i].y>=0 && frame.points[i].confidence>=0.35}
        func p(_ i:Int)->CGPoint{CGPoint(x:frame.points[i].x*sx,y:frame.points[i].y*sy)}
        guard !frame.inferenceFailed else{return}
        let bones=model == .mousePose ? [(0,1),(0,2),(1,3),(2,3),(3,4),(4,5)] : [(0,2),(1,3),(5,6),(0,1),(2,3),(1,4),(3,4)]
        ctx.setStrokeColor(CGColor(gray:1,alpha:0.9));ctx.setLineWidth(2)
        for (a,b) in bones where valid(a) && valid(b) {
            let f=p(a),t=p(b);ctx.move(to:f);ctx.addLine(to:t);ctx.strokePath()
        }
        let colors:[CGColor] = (model == .mousePose) ? [
            NSColor.red.cgColor,NSColor.orange.cgColor,NSColor.yellow.cgColor,NSColor.green.cgColor,
            NSColor.cyan.cgColor,NSColor.purple.cgColor
        ] : [
            NSColor(calibratedRed:30/255,green:127/255,blue:216/255,alpha:1).cgColor,
            NSColor(calibratedRed:18/255,green:160/255,blue:90/255,alpha:1).cgColor,
            NSColor(calibratedRed:229/255,green:64/255,blue:79/255,alpha:1).cgColor,
            NSColor(calibratedRed:138/255,green:79/255,blue:224/255,alpha:1).cgColor,
            NSColor(calibratedRed:229/255,green:143/255,blue:166/255,alpha:1).cgColor,
            NSColor(calibratedRed:242/255,green:165/255,blue:0,alpha:1).cgColor,
            NSColor(calibratedRed:95/255,green:195/255,blue:232/255,alpha:1).cgColor
        ]
        for i in frame.points.indices where valid(i) {
            let position=p(i)
            ctx.setFillColor(colors[i % colors.count]);ctx.fillEllipse(in:CGRect(x:position.x-4,y:position.y-4,width:8,height:8))
            ctx.setStrokeColor(CGColor(gray:1,alpha:0.95));ctx.strokeEllipse(in:CGRect(x:position.x-4,y:position.y-4,width:8,height:8))
        }
    }
}

/// Streaming source of saved points. For a long recording it retains at most one CSV segment.
private final class SavedPoseLocator {
    private let source:AnnotatedVideoExporter.Source
    private var index = 0
    private var rows:[NativeTrackedFrame]=[]
    private var segmentNumber = -1
    private let displayedWidth:Int
    private let displayedHeight:Int
    init(source:AnnotatedVideoExporter.Source){
        self.source=source
        let track=AVURLAsset(url:source.url).tracks(withMediaType:.video).first
        let size=track.map{CGRect(origin:.zero,size:$0.naturalSize).applying($0.preferredTransform).standardized.size}
        displayedWidth=max(1,Int(size?.width ?? 1));displayedHeight=max(1,Int(size?.height ?? 1))
    }
    struct Match {let frame:NativeTrackedFrame;let width:Int;let height:Int}
    func frame(at seconds:Double,tolerance:Double)->Match? {
        if let short=source.short {
            let timestamp=seconds - short.timeOffset
            while index+1<short.frames.count && short.frames[index+1].time <= timestamp {index+=1}
            var candidate=short.frames[index]
            if index+1<short.frames.count && abs(short.frames[index+1].time-timestamp)<abs(candidate.time-timestamp) {
                candidate=short.frames[index+1]
            }
            guard abs(candidate.time-timestamp)<=tolerance else{return nil}
            return Match(frame:candidate,width:short.videoWidth,height:short.videoHeight)
        }
        guard let long=source.long,let directory=source.directory else{return nil}
        let segments=long.completed.sorted{$0.index<$1.index}
        guard let i=segments.firstIndex(where:{$0.firstPTS-tolerance <= seconds && $0.lastPTS+tolerance >= seconds}) else{return nil}
        if segmentNumber != i {
            segmentNumber=i;rows=[];index=0
            let file=directory.appendingPathComponent(segments[i].file)
            guard let content=try? String(contentsOf:file,encoding:.utf8) else{return nil}
            let count=source.model == .mousePose ? 6 : 7
            for line in content.split(whereSeparator:\.isNewline).dropFirst() {
                let c=line.split(separator:",",omittingEmptySubsequences:false)
                guard c.count>=5+count*3,let t=Double(c[1]),let idx=Int(c[0]) else{continue}
                var pts:[NativeTrackPoint]=[]
                for k in 0..<count {
                    let n=4+k*3
                    pts.append(NativeTrackPoint(x:Double(c[n]) ?? -1,y:Double(c[n+1]) ?? -1,confidence:Double(c[n+2]) ?? 0))
                }
                rows.append(NativeTrackedFrame(index:idx,time:t,score:Double(c[3]) ?? 0,points:pts,
                    inferenceFailed:c[4+count*3] == "1"))
            }
        }
        while index+1<rows.count && rows[index+1].time <= seconds {index+=1}
        guard rows.indices.contains(index) else{return nil}
        var candidate=rows[index]
        if index+1<rows.count && abs(rows[index+1].time-seconds)<abs(candidate.time-seconds) {candidate=rows[index+1]}
        guard abs(candidate.time-seconds)<=tolerance else{return nil}
        return Match(frame:candidate,width:displayedWidth,height:displayedHeight)
    }
}
