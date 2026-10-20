# 0.5.0 upgrade scope

- Adds original RodentPose science calculation files and original-style report graphics and per-figure PNG export, by selected frame range, including bounded long-video segment readback.
- Adds RodentFlow iOS 1.3 native classic-centroid tracker and complete original 10-video-assay AssayEngine math, in an isolated module; tracking checkpoints and centroid/assay figure/CSV/JSON export.
- Adds optional annotated H.264 MP4 exporter, with sample decoding and encoding benchmark **before** export confirmation. No default render or re-inference; one-frame-at-a-time video stream. No audio stream.
- Preserves 0.4.1 Review alignment fixes, RodentLimb Swift and both existing Core ML models, source ZIP archives and old workspaces.
- Static validation performed on Linux: Swift parse of all sources, Foundation-only scientific algorithm typecheck, Xcode pbxproj lint/reference verification. Full macOS compiler and runtime testing NOT performed.
- Known limitations: native macOS ports and results need iOS numerical parity checks; MP4 coordinate/time match needs video tests, hard long-video loads bounded per segment; RodentFlow 10Hz positions accumulate in memory over duration; cannot promise no crashes on arbitrary video.
