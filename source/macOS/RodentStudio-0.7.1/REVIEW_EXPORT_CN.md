> **0.5.1**：引导流程的复核页分为“结果 / 快速复核 / 逐帧复核与导出”。下文描述的是“逐帧复核与导出”页（以及“高级”中的手动复核）；科研结果见“结果”页和 `FIGURES_PARITY_CN.md`。

# Rodent Desktop 0.3.2 — Review & Frame-range Figures

## What this version really implements

- The macOS target now compiles `NativeRunSession.swift`, `ScientificExportService.swift`, `TrackingReviewEvents.swift`, and `ReviewExportView.swift`. Previous source drops contained some of these Swift files but did not compile them into the target.
- Run → Review: Completed short-video in-memory pose runs and completed long-video segment manifests are made available to **Start Here → Review & export** and the standalone Review / Results pages. A completed long-video results folder can also be reopened.
- Short runs: inspect an actual decoded video frame with the tracked six or seven keypoints; navigate by frame slider or Tracking Events list. Tracking QC events are grouped into consecutive runs of `Inference failed`, `No detection`, and `Low confidence` and are **not** called animal behaviors.
- Long runs: initial list reports segments with inference failures. Click **Index exact QC events** to inspect completed per-frame CSV segments individually; only one completed segment is read at a time. The event list is capped at 25,000 intervals to prevent unbounded UI memory.
- RodentLimb only: optional **Show original RodentLimb behavior events** calls the original Swift Cylinder / TST / Gait analyzer after a matching experiment is selected. Default assay parameters and saved desktop calibration are used. Scientific parity and human scoring validation are **not established**. Its bouts/contacts/strides can be inspected separately from QC events.
- Review annotations: an event can be marked Accepted or Flagged; annotations and reviewer notes are exported as separate metadata. They **do not silently edit raw keypoints or original analyzer scores**.

## Frame-range export

Use **Start frame** and **End frame**, **inclusive and zero-based**, or select an event then press **Use range**. Only the selected frames enter PNG figure calculations. Data from other frames remain in the original output.

Optional exports:

| Output | Short | Long | Notes |
|---|---|---|---|
| Raw pose CSV | Yes | Per completed segment | No interpolation or destructive filtering |
| QC-screened CSV | Yes | No | Eligibility flag, original coordinates retained |
| Frame/segment QC CSV | Yes | Yes | Segmented long QC is distinct from per-frame QC |
| Provenance JSON | Yes | Yes | Source, model, optional setup and figure frame selection |
| Trajectory PNG | Yes | Yes | Generated from processed pose coordinates, selected frame range |
| Confidence PNG | Yes | Not yet | Processed box confidence, selected frame range |
| Annotated still PNG | Yes | Not yet | Only current frame; optional |
| RodentLimb behavior-event timeline PNG | After analyzer run | Not yet | Experimental, not publication-validated |
| Segment QC timeline PNG | No | Yes | Segment-level inference failure fraction |
| Annotated movie | **Not implemented** | **Not implemented** | Deliberately disabled, no default video render |
| Review annotations JSON | Yes | Yes | Separate decisions/notes, no edits to raw outputs |

**Important:** RodentPose and RodentFlow behavioral analyzers still require a science-parity port. The existing figures are tracking/QC figures, **not yet all assay-specific endpoint figures**. RodentLimb original analyzer event plotting remains experimental.

## Installation

```bash
cd ~/Downloads
unzip RodentDesktopNativeReviewExports.zip
cd RodentDesktopNativeReviewExports
python3 install_models.py
open RodentDesktopNative.xcodeproj
```

Select My Mac, build (⌘B), run (⌘R). Models are intentionally not redistributed in the ZIP; the model installer uses the previously configured local model locations.

## Manual acceptance tests on macOS

1. Run a short RodentPose video, then open Review. Confirm the model reads RodentPose, six keypoints and clicking a QC event seeks to that frame. If there are no QC events, the list should state that (not generate false events).
2. Set frame range `200...450`, export trajectory PNG, confidence PNG, full raw CSV and JSON. Verify raw CSV retains all frame rows, while figure is cropped to the selected observations. Check frame range in `qc_provenance.json` and `review_annotations.json`.
3. Repeat with Cylinder V2 (seven keypoints), and optionally the original RodentLimb event button with appropriate assay/calibration. Confirm the new event timeline is explicitly marked experimental.
4. Open an existing 10+ minute long-video result directory, run **Index exact QC events**, choose a limited frame range, export a figure and check that Xcode Instruments shows bounded RAM rather than a whole-video tracking allocation.
5. Check `App Sandbox` file selections, repeated saves, folder permissions, and event counts. This Linux-built archive has **not** been compiled with macOS Xcode/SDK. Report Xcode build errors for correction.

Do not use these outputs for formal inference or scientific publication until original iOS algorithms, coordinate conventions and manual scorer agreement have been verified with reference recordings.
