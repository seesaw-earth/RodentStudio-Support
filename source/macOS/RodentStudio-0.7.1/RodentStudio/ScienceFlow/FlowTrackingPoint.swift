import Foundation
struct FlowTrackingPoint: Codable, Identifiable, Hashable, Sendable {
    var id: Int { frameIndex }
    let frameIndex: Int
    let clipTimeSeconds: Double
    let videoTimeSeconds: Double

    let imageXNormalized: Double
    let imageYNormalized: Double

    let arenaXNormalized: Double
    let arenaYNormalized: Double

    let xCentimeters: Double
    let yCentimeters: Double
    let confidence: Double
    let interpolated: Bool
    let zone: String
    /// Fraction of arena pixels that changed since the previous 10 Hz sample (freezing analysis).
    var motionIndex: Double? = nil
    /// Area of the selected foreground component as a fraction of the arena area.
    var blobAreaFraction: Double? = nil
}

struct FlowMazeEvent: Codable, Hashable, Identifiable {
    var id: String { "\(eventIndex)-\(timeSeconds)-\(toZone)" }
    let eventIndex: Int
    let timeSeconds: Double
    let fromZone: String
    let toZone: String
}


struct FlowFullAnalysisResult {
 let durationSeconds: Double
 let processingFPS: Double
 let points: [FlowTrackingPoint]
 let mazeEvents: [FlowMazeEvent]
 var markersCM: [String: FlowArenaPoint] = [:]
}
struct FlowAnalysisProgressSnapshot: Equatable {
 let fraction: Double
 let processedSamples: Int
 let estimatedTotalSamples: Int?
 let elapsedSeconds: Double
 let remainingSeconds: Double?
}
enum FlowMazeEventAnalyzer {
 static func events(points: [FlowTrackingPoint], arenaShape: FlowArenaShape) -> [FlowMazeEvent] {
   guard arenaShape.isMaze else { return [] }
   var output: [FlowMazeEvent] = []
   var prev = ""
   for point in points where !point.interpolated {
     if point.zone != prev {
       if !prev.isEmpty && !point.zone.isEmpty { output.append(FlowMazeEvent(eventIndex: output.count, timeSeconds: point.videoTimeSeconds, fromZone: prev, toZone: point.zone)) }
       prev = point.zone
     }
   }
   return output
 }
}
func flowLoc(_ s: String) -> String { s }
