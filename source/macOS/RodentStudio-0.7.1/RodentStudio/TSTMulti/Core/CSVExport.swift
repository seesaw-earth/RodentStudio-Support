import Foundation

public enum CSVExport {

    static func f(_ x: Double?, _ digits: Int = 2) -> String {
        guard let x, x.isFinite else { return "" }
        return String(format: "%.\(digits)f", x)
    }

    public static func summary(_ r: TSTMultiAnalysisResult, videoName: String) -> String {
        let nMin = r.summaries.first?.perMinuteImmobileSec.count ?? 0
        // Windows are measured from each mouse's own suspension (onset_s after the analysis start);
        // "primary" = the last part of the standard test (minutes 2–6 by default).
        var lines = ["video,chamber,analysed,immobile_total_s,immobile_pct,immobile_last\(Int(r.settings.lastWindowSec))s_s,"
                     + "latency_s,bouts,mean_bout_s,longest_bout_s,no_mouse_pct,"
                     + "suspended_at_video_s,test_length_s,immobile_early_s,immobile_primary_s,immobile_primary_pct,immobile_test_s,immobile_test_pct,"
                     + "test_coverage,mobility_intensity_pct_body,"
                     + (1...max(1, nMin)).map { "min\($0)_immobile_s" }.joined(separator: ",")]
        for s in r.summaries {
            var row = [videoName, "\(s.chamber)", s.analysed ? "yes" : "no", f(s.immobileTotalSec), f(s.immobilePercent),
                       f(s.immobileLastWindowSec), f(s.latencySec), "\(s.bouts)", f(s.meanBoutSec),
                       f(s.longestBoutSec), f(s.noMousePercent),
                       f(s.onsetSec.map { $0 + r.settings.startSec }), f(s.testLengthSec, 0), f(s.earlyImmobileSec), f(s.primaryImmobileSec),
                       f(s.primaryImmobilePercent), f(s.testImmobileSec), f(s.testImmobilePercent),
                       f(s.testCoverage, 3), f(s.mobilityIntensity)]
            row += s.perMinuteImmobileSec.map { f($0, 1) }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func framewise(_ r: TSTMultiAnalysisResult) -> String {
        var lines = ["chamber,time_s,motion_smoothed_pct,pixel_change_pct,shape_change_pct,immobile,no_mouse,area_px,cx,cy,box_change_pct,box_mouse_present"]
        for (ci, tr) in r.traces.enumerated() {
            for k in tr.time.indices {
                lines.append([
                    "\(ci + 1)", f(tr.time[k], 3), f(tr.motion[k], 3), f(tr.pixelPercent[k], 3),
                    f(tr.shapePercent[k], 3), tr.immobile[k] ? "1" : "0", tr.noMouse[k] ? "1" : "0",
                    f(tr.area[k], 0), f(tr.cx[k], 1), f(tr.cy[k], 1),
                    k < tr.boxPercent.count ? f(tr.boxPercent[k], 3) : "",
                    k < tr.boxPresent.count ? (tr.boxPresent[k] ? "1" : "0") : "",
                ].joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Key-frame scan: when each mouse first appeared stably, and the chosen analysis window.
    public static func keyFrame(_ k: KeyFrameResult, keyTime: Double?, analysisStart: Double,
                                analysisDuration: Double, detector: String) -> String {
        var lines = ["# detector: \(detector)",
                     "# key_frame_s (all selected mice detected): \(f(k.keyTime))",
                     "# analysis_start_s: \(f(analysisStart)), analysis_duration_s: \(f(analysisDuration))",
                     "# all_present_end_s (a mouse missing again): \(f(k.allPresentEnd))",
                     "chamber,selected,hung_at_s,presence_pct"]
        for c in 0..<k.selected.count {
            let pres = k.presence[c]
            let pct = pres.isEmpty ? 0 : 100 * Double(pres.filter { $0 }.count) / Double(pres.count)
            lines.append("\(c + 1),\(k.selected[c] ? "yes" : "no"),\(f(k.hungAt[c])),\(f(pct, 1))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func settingsJSON(_ r: TSTMultiAnalysisResult) -> String {
        struct Out: Codable { var settings: AnalysisSettings; var walls: [Double]; var y0: Int; var y1: Int
                              var imageWidth: Int; var imageHeight: Int; var fps: Double; var notes: [String] }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let o = Out(settings: r.settings, walls: r.layout.walls, y0: r.layout.y0, y1: r.layout.y1,
                    imageWidth: r.layout.imageWidth, imageHeight: r.layout.imageHeight, fps: r.fps, notes: r.layout.notes)
        return (try? enc.encode(o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
