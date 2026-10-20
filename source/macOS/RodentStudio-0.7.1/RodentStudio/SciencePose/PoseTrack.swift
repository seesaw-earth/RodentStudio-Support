// RodentPose iOS 1.0 scientific algorithm port; only PoseTrack name and localization/zone invocation adapted.
// RPPoseTrack.swift — per-frame keypoints for one session (1 or 2 animals), compact binary storage
// and the raw keypoint CSV (same columns as MousePose 1.0 for a single animal).

import Foundation

/// One animal's detection in one frame: box confidence and 6 × (x px, y px, conf).
struct AnimalPose {
    var conf: Float
    var x: [Float]
    var y: [Float]
    var kconf: [Float]

    static let missing = AnimalPose(conf: 0, x: [Float](repeating: 0, count: kKeypointCount),
                                    y: [Float](repeating: 0, count: kKeypointCount),
                                    kconf: [Float](repeating: 0, count: kKeypointCount))

    var detected: Bool { conf > 0 && x.count == kKeypointCount && kconf.count == kKeypointCount }

    /// Mean of keypoint positions with confidence above `minConf` (used for identity matching).
    func centroid(minConf: Float = 0.3) -> V2? {
        guard detected else { return nil }
        var sx = 0.0, sy = 0.0, n = 0.0
        for k in 0..<kKeypointCount where kconf[k] >= minConf {
            sx += Double(x[k]); sy += Double(y[k]); n += 1
        }
        return n > 0 ? V2(sx / n, sy / n) : nil
    }
}

struct RPPoseTrack {
    static let stride = kKeypointCount * 3

    var animalCount: Int
    var fps: Double
    var frameWidth: Double
    var frameHeight: Double
    var frameStride: Int
    var frameIndex: [Int32] = []
    var time: [Double] = []
    /// Box confidence per frame per animal (0 = not detected).
    var detConf: [Float] = []
    /// Per frame, per animal: 6 × (x, y, conf), pixel coordinates of the upright frame.
    var kp: [Float] = []
    var processedUntil: Double = 0
    var complete = false
    var msPerFrame: Double = 0

    init(animalCount: Int, fps: Double, frameWidth: Double, frameHeight: Double, frameStride: Int) {
        self.animalCount = max(1, animalCount)
        self.fps = fps
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.frameStride = max(1, frameStride)
    }

    var count: Int { time.count }
    var frameSize: V2 { V2(frameWidth, frameHeight) }
    var lastFrameIndex: Int { frameIndex.last.map(Int.init) ?? -1 }

    // MARK: Access

    func conf(_ i: Int, _ a: Int = 0) -> Float { detConf[i * animalCount + a] }

    func pose(_ i: Int, _ a: Int = 0) -> AnimalPose {
        let base = (i * animalCount + a) * RPPoseTrack.stride
        var xs = [Float](repeating: 0, count: kKeypointCount)
        var ys = xs, cs = xs
        for k in 0..<kKeypointCount {
            xs[k] = kp[base + k * 3]
            ys[k] = kp[base + k * 3 + 1]
            cs[k] = kp[base + k * 3 + 2]
        }
        return AnimalPose(conf: conf(i, a), x: xs, y: ys, kconf: cs)
    }

    /// Raw pixel position and confidence of keypoint `k`.
    @inline(__always)
    func point(_ i: Int, _ a: Int, _ k: Int) -> (x: Float, y: Float, c: Float) {
        let base = (i * animalCount + a) * RPPoseTrack.stride + k * 3
        return (kp[base], kp[base + 1], kp[base + 2])
    }

    mutating func append(frame: Int, time t: Double, animals: [AnimalPose]) {
        frameIndex.append(Int32(clamping: frame))
        time.append(t)
        for a in 0..<animalCount {
            let p = a < animals.count ? animals[a] : AnimalPose.missing
            let ok = p.detected
            detConf.append(ok ? p.conf : 0)
            for k in 0..<kKeypointCount {
                kp.append(ok ? p.x[k] : 0)
                kp.append(ok ? p.y[k] : 0)
                kp.append(ok ? p.kconf[k] : 0)
            }
        }
    }

    /// Index of the processed frame closest to time `t` (binary search).
    func nearestIndex(to t: Double) -> Int? {
        guard !time.isEmpty else { return nil }
        var lo = 0, hi = time.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if time[mid] < t { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0 && abs(time[lo - 1] - t) < abs(time[lo] - t) { return lo - 1 }
        return lo
    }

    // MARK: Summary

    func summary() -> PoseSummary {
        var s = PoseSummary()
        s.frames = count
        s.animalCount = animalCount
        var detected = 0
        var confSum = 0.0, confN = 0.0
        for i in 0..<count {
            var any = false
            for a in 0..<animalCount where conf(i, a) > 0 {
                any = true
                confSum += Double(conf(i, a))
                confN += 1
            }
            if any { detected += 1 }
        }
        s.detectedFrames = detected
        s.meanConfidence = confN > 0 ? confSum / confN : 0
        s.msPerFrame = msPerFrame
        s.processedUntil = processedUntil
        s.complete = complete
        return s
    }

    // MARK: Binary storage

    private struct Header: Codable {
        var version = 2
        var animalCount: Int
        var fps: Double
        var frameWidth: Double
        var frameHeight: Double
        var frameStride: Int
        var count: Int
        var processedUntil: Double
        var complete: Bool
        var msPerFrame: Double
    }

    enum StorageError: LocalizedError {
        case badFile
        var errorDescription: String? { RPTexts.tr("姿态数据文件已损坏或版本不兼容") }
    }

    func encoded() throws -> Data {
        let header = Header(animalCount: animalCount, fps: fps, frameWidth: frameWidth, frameHeight: frameHeight,
                            frameStride: frameStride, count: count, processedUntil: processedUntil,
                            complete: complete, msPerFrame: msPerFrame)
        let h = try JSONEncoder().encode(header)
        var data = Data("MPT2".utf8)
        var len = UInt32(h.count).littleEndian
        withUnsafeBytes(of: &len) { data.append(contentsOf: $0) }
        data.append(h)
        frameIndex.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        time.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        detConf.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        kp.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    static func decode(_ data: Data) throws -> RPPoseTrack {
        guard data.count >= 8, String(decoding: data.prefix(4), as: UTF8.self) == "MPT2" else { throw StorageError.badFile }
        var len: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &len) { data.copyBytes(to: $0, from: data.startIndex + 4 ..< data.startIndex + 8) }
        let hl = Int(UInt32(littleEndian: len))
        var offset = data.startIndex + 8
        guard data.endIndex - offset >= hl else { throw StorageError.badFile }
        let header = try JSONDecoder().decode(Header.self, from: data.subdata(in: offset ..< offset + hl))
        offset += hl
        let n = header.count, a = max(1, header.animalCount)

        func read<T>(_ count: Int, _ type: T.Type) throws -> [T] {
            let bytes = count * MemoryLayout<T>.stride
            guard bytes >= 0, data.endIndex - offset >= bytes else { throw StorageError.badFile }
            let out = [T](unsafeUninitializedCapacity: count) { buf, initialized in
                let raw = UnsafeMutableRawBufferPointer(buf)
                data.copyBytes(to: raw, from: offset ..< offset + bytes)
                initialized = count
            }
            offset += bytes
            return out
        }

        var t = RPPoseTrack(animalCount: a, fps: header.fps, frameWidth: header.frameWidth, frameHeight: header.frameHeight, frameStride: header.frameStride)
        t.frameIndex = try read(n, Int32.self)
        t.time = try read(n, Double.self)
        t.detConf = try read(n * a, Float.self)
        t.kp = try read(n * a * RPPoseTrack.stride, Float.self)
        t.processedUntil = header.processedUntil
        t.complete = header.complete
        t.msPerFrame = header.msPerFrame
        return t
    }

    // MARK: Raw keypoint CSV

    /// `frame,time_s,det_conf,<kp>_x,<kp>_y,<kp>_conf…` — pixel coordinates of the upright frame,
    /// origin top-left. Two animals: columns prefixed `m1_` / `m2_`.
    func rawCSV() -> Data {
        var header = ["frame", "time_s"]
        for a in 0..<animalCount {
            let pre = animalCount > 1 ? "m\(a + 1)_" : ""
            header.append("\(pre)det_conf")
            for n in kKeypointNames { header += ["\(pre)\(n)_x", "\(pre)\(n)_y", "\(pre)\(n)_conf"] }
        }
        var w = ByteWriter(capacity: (count + 1) * header.count * 7)
        w.row(header)
        for i in 0..<count {
            w.write(String(frameIndex[i])); w.comma()
            w.write(FastFormat.fixed(time[i], 3))
            for a in 0..<animalCount {
                let c = conf(i, a)
                w.comma(); w.write(FastFormat.fixed(Double(c), 3))
                for k in 0..<kKeypointCount {
                    if c > 0 {
                        let p = point(i, a, k)
                        w.comma(); w.write(FastFormat.fixed(Double(p.x), 1))
                        w.comma(); w.write(FastFormat.fixed(Double(p.y), 1))
                        w.comma(); w.write(FastFormat.fixed(Double(p.c), 3))
                    } else {
                        w.comma(); w.comma(); w.comma()
                    }
                }
            }
            w.newline()
        }
        return w.data
    }
}

// MARK: - Identity assignment for two animals

enum IdentityTracker {
    /// Orders up to two detections so that each keeps the identity of the closest previous animal.
    static func assign(_ detections: [AnimalPose], previous: [V2?]) -> [AnimalPose] {
        var dets = detections.filter { $0.detected }
        dets.sort { $0.conf > $1.conf }
        dets = Array(dets.prefix(2))
        guard previous.count == 2 else {
            return dets + [AnimalPose](repeating: .missing, count: max(0, 2 - dets.count))
        }
        let c = dets.map { $0.centroid() }
        func cost(_ d: Int, _ a: Int) -> Double {
            guard d < c.count, let p = c[d], let q = previous[a] else { return 1e6 }
            return p.distance(to: q)
        }
        switch dets.count {
        case 0:
            return [.missing, .missing]
        case 1:
            if previous[0] == nil && previous[1] == nil { return [dets[0], .missing] }
            return cost(0, 0) <= cost(0, 1) ? [dets[0], .missing] : [.missing, dets[0]]
        default:
            let keep = cost(0, 0) + cost(1, 1)
            let swap = cost(0, 1) + cost(1, 0)
            return keep <= swap ? [dets[0], dets[1]] : [dets[1], dets[0]]
        }
    }
}
