# Source-preserving integration status

Original source files preserved unchanged in `OriginalAppSources` (RodentFlow 1.3, RodentPose 1.0, RodentLimb 1.1.2). The Xcode Target does not compile those iOS-only projects as-is because they use UIKit and have overlapping type names. RodentLimb native Swift analyzers already compiled into the target. Other source libraries are references awaiting platform adaptation and parity tests.

## Visible experiment catalog
- RodentPose: 16 paradigms, six-keypoint Core ML model required for every pose-based protocol.
- RodentLimb: 3 paradigms, seven-keypoint Cylinder V2 Core ML and native Swift analyzers.
- RodentFlow: 10 **video-input** presets; excludes marble burying, sucrose preference, beam walking, manual gait, two-armed bandit and custom table. Uses classic centroid (not a YOLO model), but the macOS tracker is not yet ported.

**Important:** Registrations in Experiment and Assay Catalog do not activate missing analysis code. Full fidelity of protocol/calibration/metrics/stats/manual entry needs continued porting and tests. Existing project identifiers are not changed.

### Workflow 0.3.1
A guided six-stage workflow, mouse-draggable arena handles, 3x pointer loupe and basic per-assay editable setup are now implemented. This does not imply that original scientific scores, all parameter editors, or manual event QC have been ported. See `MIGRATION_MOUSE_PARITY.md`.

### 0.4.0
- Calibration is now per module and ported from each original app: RodentPose (`Calibration/Pose*.swift`, `Views/PoseCalibrationEditor.swift`), RodentFlow (`Calibration/FlowSetupModel.swift`, `Views/FlowCalibrationEditor.swift`) and RodentLimb (`Views/LimbCalibrationEditor.swift` with the existing `Calibration` / `AssayParams`). `Calibration/TaskSetup.swift` maps every desktop task to its own app. See `CALIBRATION_PARITY_CN.md`.
- The guided workflow follows the apps (task → video & animal → calibrate → analyse → review). The model is chosen by the task; manual model choice lives only under Advanced.
- Guided runs use the segmented engine in the app container (resume, batch). RodentLimb events use the video's saved RodentLimb calibration and parameters.
- Not yet ported: RodentFlow tracker and metrics, RodentPose behavioural metrics. No macOS build was possible in the authoring environment.
