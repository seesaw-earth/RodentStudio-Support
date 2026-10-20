# Long-video research & architecture, 17 October 2026

## Confirmed Apple guidance (not a benchmark of this application)
1. `AVAssetReaderTrackOutput`: request a decoder-native pixel format to avoid conversion; for H.264 consider NV12; on macOS Apple documents 422YpCbCr8 as preferred for video and 32ARGB for RGB workflows. Original Core ML preprocessing currently uses BGRA and must be scientifically checked before changing pixel formats. https://developer.apple.com/documentation/AVFoundation/AVAssetReaderTrackOutput
2. `AVAssetReaderOutput.alwaysCopiesSampleData`: Apple documentation recommends disabling extra copies for read-only samples; note that some current SDK views deprecate the property, so check your deployment target and availability. https://developer.apple.com/documentation/avfoundation/avassetreaderoutput
3. `WWDC 2025 Improve memory usage and performance with Swift`: reduce heap allocations and favor bounded/reusable buffers. https://developer.apple.com/videos/play/wwdc2025/312/
4. `WWDC 2025 Code-along: Elevate an app with Swift concurrency`: move expensive operations off the main actor and guard access to shared state. https://developer.apple.com/videos/play/wwdc2025/270/
5. `ProcessInfo`: balance user-initiated work and sudden termination correctly, avoid unnecessary disabling of sleep for all user sessions. https://developer.apple.com/documentation/foundation/processinfo
6. `FileHandle.synchronize()`: sync each finished segment before marking it completed in the JSON checkpoint. https://developer.apple.com/documentation/foundation/filehandle/synchronize%28%29

## 2026 API developments considered
- Apple's current `AVAssetReader` documentation exposes a typed `outputProvider(for:)` in addition to the older `addOutput`/`copyNextSampleBuffer` flow. The older `startReading()` is now marked deprecated in favor of `start()`, so the current code should be regarded as an **API compatibility prototype**, not the newest interface: https://developer.apple.com/documentation/avfoundation/avassetreader and https://developer.apple.com/documentation/avfoundation/avassetreader/startreading%28%29
- `AVSampleBufferGenerator` and its batch mechanism support grouped/deferred sample I/O, particularly relevant for random-access preview or specialized media formats, but do not by themselves solve memory growth or checkpoint consistency for long sequential analysis: https://developer.apple.com/documentation/avfoundation/avsamplebuffergenerator and https://developer.apple.com/documentation/avfoundation/avsamplebuffergeneratorbatch
- Apple's WWDC26 engineering guidance recommends lazy loading for large collections (50K-500K records), avoiding SwiftUI recomputation, and benchmarking with MetricKit/Instruments: https://developer.apple.com/videos/play/wwdc2026/8003/
- WWDC26 Instruments 27 highlights app-responsiveness profiling across allocation, reference counting, I/O, and scheduling: https://developer.apple.com/videos/play/wwdc2026/268/

The shipped implementation deliberately uses the previously tested `AVAssetReader` API surface to retain macOS 14+ deployment compatibility; a migration to typed output providers should be done in a separate, benchmarked change. The newest API is not automatically the safest for an unvalidated assay pipeline.

## Engineering requirements not solved by an API alone
- **Constant memory**: never retain all video frames or all raw keypoint rows. Keep one decoded frame + Core ML request + 32-KB CSV buffer.
- **Checkpoint**: commit segment_NNN.csv (rename after close and sync), then atomically update manifest; resume skips only complete segments with files present.
- **Backpressure**: one decode→inference→write loop; do not queue unbounded asynchronous predictions. Later optimize with a bounded 2-4-buffer pipeline only after profiling.
- **Identities**: enforce source fingerprint, model, video length and segment duration before resuming.
- **Timestamps**: use each CMSampleBuffer PTS, not fps-derived frame numbers, especially variable-frame-rate input.
- **Scientific semantics**: windowed/streaming event analyzers must retain boundary state (previous landmark, pending dwell, freezing bout, gait stride etc.) across segments. Do not compute independent per-segment assay averages then average them.
- **Quality**: simulate forced termination, disk full, HEVC/H.264/VFR, long/no-detection intervals, thermal throttling, and offline sandbox paths. Compare CSV rows across segmented vs continuous reference on same video.
- **Efficiency**: only optimize pixel format, frame stride and batch size after assessing scientific effects, including effects on behavior markers. Prefer Instruments Allocations, Time Profiler, Metal System Trace, and Activity Monitor RSS.

## Scope of this development build
This version implements segmented **raw Core ML pose extraction only** for MousePose6 and Cylinder V2. The original classic RodentFlow tracker itself is preserved but still needs a macOS-compatible port using the same underlying thresholds and arena mapping. Long-video processing for RodentFlow must have a different track state/checkpoint schema and may require temporal background initialization; it must not be routed through the neural model path.
