# RodentPose — on-device mouse pose and behavior analysis

**Free and open-source research tool · iOS 17+ · English / 简体中文**

RodentPose tracks six mouse landmarks (nose, left/right ears, neck, body center, tail base) from video on an iPhone or iPad, then calculates adjustable behavioral readouts for 16 assay modes. Built for overhead rodent recordings and quick review of experimental videos—not as a replacement for hand-scored behavioral ground truth.

**中文完整说明：** [README.zh-Hans.md](README.zh-Hans.md)

## Open the Xcode project

1. Open **`RodentPose.xcodeproj`** with **Xcode 26+** (required for current App Store submissions). Swift Package Manager resolves `UltralyticsYOLO` on first open. The included Core ML model retains its technical resource name `MousePose6_960_int8.mlpackage`.
2. Select the **RodentPose** target → **Signing & Capabilities** → your Apple Developer Team. Bundle identifier: `com.ziqingshi.RodentStudio`. Create/register this App ID in your Apple Developer account if needed.
3. Select an iPhone/iPad on **iOS 17+**, then **Product → Run**. Confirm the model loads and test import → calibration → inference → review → export using a video you are authorized to use.
4. In **RodentPose → Settings (gear) → Language**, choose **Follow System / 中文 / English**. Changes apply in-app immediately and do not change the iPhone's language. The choice is saved locally. UI strings are in `RodentPose/Localizable.xcstrings`; translated runtime values are in `RodentPose/EnglishTranslations.json` and `RodentPose/L10nPatterns.json`.
5. Before public release, read [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## What it does

- Imports recordings from Photos or Files; stores sessions locally.
- On-device YOLO / Core ML pose detection, customizable frame sampling, two-animal mode (with identity limitations), progress and resume.
- Arena calibration: rectangular/circular arenas and plus/Y/T mazes; object and shelter markers, adjustable dimensions and thresholds.
- Touch-friendly calibration: handles have a larger hit target, locally preview their changes while dragging, and commit once on release. Three-chamber analysis adds independently movable purple L/R divider handles (the center region can be shifted or resized, rather than fixed to symmetrical side chambers).
- 16 modes including open field, novel object recognition, elevated plus maze, Barnes/Y/T maze, light–dark box, three-chamber sociability, social interaction, dyadic interaction, head direction, freezing and more.
- Video review with pose overlays, interactive behavioral zones and a 2-second trail that is cleaned and smoothed for display (jumps removed; metrics are unaffected).
- Phase / condition per session: paradigm presets or your own labels added with “+”; optional.
- Analysis screens show controls and results only; how-to notes, parameter and measure definitions, figure notes, quality details and the Methods text are one tap away behind small ⓘ buttons.
- Exports keypoint CSV, per-frame CSV, metrics CSV, JSON reports and multi-session summary CSV.

## Language and reproducibility

- **Languages:** In-app switcher for Follow System / Simplified Chinese / English; no system Settings changes needed. Metadata drafts exist in `AppStore/en-US.md` and `AppStore/zh-Hans.md`.
- **Stable scientific output:** Numeric metrics, enum values, technical keypoint names, CSV/JSON keys and machine-generated descriptions are always in **English**, including Methods and warnings, regardless of UI language. Researcher-entered identifiers/notes are preserved verbatim (enter them in English if an entirely English dataset is required). See `LANGUAGE_AND_DATA_POLICY.md`.
- **Model filename:** `MousePose6_960_int8.mlpackage` must *not* be renamed without also updating `kModelName` and verifying runtime loading. The model name is not the App brand.
- **Scientific validity:** Landmark geometry is a proxy, not confirmed nose sniffing/freezing/social behavior. Validate against manual annotation before making scientific claims. Multi-animal identity may switch under overlap.

## Open-source and release status

The application source is intended to be released under **GNU AGPL-3.0-only** (see [LICENSE](LICENSE)). Third-party components, model weights and training datasets require **separate provenance and redistribution checks**. A `LICENSE` file alone does *not* establish redistribution rights for third-party weights or training data.

**Not yet release-ready:** This environment can parse the Swift files and inspect the Xcode project but cannot run Xcode/iOS device tests. The bundled Core ML model's upstream training-data and weight licenses are *not established by this archive*. App Store compatibility with the AGPL terms should be reviewed before distribution. The App Store privacy answers and public support URL also need confirmation.

See [MODEL_PROVENANCE.md](MODEL_PROVENANCE.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the release checklist.

## Directory map

```text
RodentPose.xcodeproj/         Xcode project
RodentPose/                   SwiftUI app, Core ML model, localized resources
RodentPose/Localizable.xcstrings
RodentPose/L10nPatterns.json  Translatable dynamic messages
AppStore/en-US.md             English App Store copy
AppStore/zh-Hans.md           简体中文 App Store 文案
AppStore/REVIEW_NOTES.md      Review-team instructions
AppStore/SCREENSHOT_PLAN.md  Bilingual screenshots checklist
AppStore/PRIVACY_POLICY.md    Bilingual privacy policy draft; verify before posting
RELEASE_CHECKLIST.md          Step-by-step bilingual checklist
docs/                         Word release guide
MODEL_PROVENANCE.md           Model rights & evaluation sign-off
THIRD_PARTY_NOTICES.md        Dependencies & license cautions
LICENSE                       GNU AGPL-3.0
```

## Attribution / contribution

User-contributed code and third-party libraries retain their respective copyrights; see their original sources and licenses. Contributions should preserve the scientific reporting schema and provide tests for new behavior definitions. Add training/evaluation scripts and shareable validation media to the repository only after data authorization.
