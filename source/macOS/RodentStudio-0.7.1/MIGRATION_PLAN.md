# Migration plan — Rodent Desktop 0.2.0 → Native Xcode macOS

## Goal and non-goals

- Retain assay definitions, keypoint ordering, methods provenance, deterministic analysis, QC and animal-level statistics.
- Replace PySide6 with SwiftUI; PyAV/OpenCV with AVFoundation/Vision; ONNX Runtime / Python `coremltools` with Apple's Core ML runtime.
- Use **the existing trained models**; do not change input size, weights, or sampling without explicit validation.
- Do not claim a feature is ported until real-video end-to-end parity and QC checks pass.

## Phases

**Phase 0 — Done in this scaffold:** native `.xcodeproj`, sandbox entitlements, SwiftUI shell and local project store, native video metadata import, original RodentLimb Swift source integrated in the main Target, optional imported-pose analysis. Models are intentionally absent.

**Phase 1 — Pose runtime:** Add `MousePose6_960_int8.mlpackage` and `CylinderMousePoseV2.mlpackage`, write AVAssetReader frame streaming with explicit video orientation/timestamps, Vision / Core ML preprocessor and original output decoders. Confirm six- and seven-landmark ordering and exact ROI coordinate frames. Add queue/cancel/resume.

**Phase 2 — RodentLimb UI:** Cylinder calibration (rim/floor), event editor, TST window and clasping, gait walkway scale and QC, interactive review, provenance and exports. Reuse original analyzers. Compare every metric, event and warnings against iOS 1.1.2 on identical saved PoseTracks.

**Phase 3 — RodentPose:** Port original Python analyzers (open-field, NOR, EPM, three-chamber, pose-only first). Preserve arena zones, trials, handling of missing keypoints, units and warnings. Use golden fixtures from 0.2.0, not hand-written approximations. Other paradigms remain disabled until ported.

**Phase 4 — Study database / stats / export:** Migrate `.rodentproj` schema with stable IDs, groups/animals/sessions, independent observations (one per animal), phase segregation, QC exclusions, t/U/paired/ANOVA/Kruskal statistics, multiple-comparisons correction, plots and reproducible exports. Build explicit conversion with back-up / round-trip tests; never silently rewrite old projects.

**Phase 5 — Mac App Store:** Verify Sandbox file permissions and security-scoped bookmarks in background analysis; codesign; supply icon, screenshots and disclosures; license check for AGPL/Ultralytics/models; release/TestFlight and reviewer sample data. Final Archive via Xcode.

## Package elimination

| Legacy Python dependency | Native replacement |
|---|---|
| PySide6 / Qt | SwiftUI + AppKit where macOS-specific |
| PyAV / OpenCV / FFmpeg | AVFoundation / VideoToolbox / Core Image (where applicable) |
| ONNX Runtime / Python coremltools | Core ML / Vision |
| NumPy / SciPy | Accelerate/vDSP plus explicit Swift implementations when scientifically required |
| Matplotlib | Swift Charts and vector exports (PDF/SVG needs validated native exporter) |
| Python runtime / Conda / PyInstaller | Xcode-built and signed native app |
| Openpyxl | Native CSV primarily, Excel export only if later required |

Apple frameworks are not always API-equivalent to the legacy libraries: computational parity is an explicit requirement, not an assumption.

## Scientific audit boundaries

- Swift analyzers are present, but no statement of equivalence to actual video/CPU or human scores is warranted until validation.
- The existing iOS Core ML model may depend on Vision's `scaleFit` preprocessing; do not replace this silently with simple image resizing.
- For side-view cylinder, calibration floor geometry and 7-landmark frame orientation are mandatory.
- Mac native workspace uses a **new JSON format**; old `.rodentproj` is only inspected read-only. Full compatibility remains Phase 4.
