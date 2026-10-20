# Calibration interaction fix / 标定交互修复

This is an edited copy of the uploaded RodentPose iOS 1.0 Xcode project. It is **not** a device-tested release build.

## What's changed / 更新内容

- Three-chamber has two **purple L/R divider handles**, allowing independent left and right limits of the middle chamber. Yellow 1–4 continue to control the four outer arena corners; cyan L/R remain the social cup markers. The current two-divider implementation follows the outer rectangle's perspective mapping. For irregular or visibly curved/slanted partitions not explained by camera perspective, four independent partition endpoint handles would be a separate enhancement.
- Three-chamber middle width and its center offset are persisted in `AnalysisParams` as `centerChamberFraction` and `centerChamberOffset`. Previous `session.json` files have no offset; the custom decoder defaults it to `0`, preserving centered legacy behavior.
- All calibration handles now have a wider touch target (56 pt, from 44 pt), a stable named gesture coordinate space and high-priority drag gestures to reduce conflicts with the page's `ScrollView`.
- During dragging, a local draft controls the marker and zone overlays; the entire `Session` is written only when the gesture ends. That avoids re-triggering expensive session-level updates on every finger movement; after release, the existing re-analysis and persistence logic remains unchanged.
- Reset calibration also resets center-chamber dividers to centered thirds.
- Two newly added onscreen tips have English and Simplified Chinese translations.

## Validation performed / 已验证

- `swiftc -frontend -parse RodentPose/*.swift` (syntax only).
- `python tools/check_localizations.py` (passed: 883 strings / 91 dynamic entries / zero errors).
- Static source checks and divider geometry bounds sanity checks.

## Before distribution: required on-device tests / 上架前必测

1. Three-chamber: drag purple left divider only, then right divider only. Verify center zone follows and metrics change after release.
2. Move each outer corner; check both divider handles and partition lines remain aligned after perspective correction.
3. Move cyan L/R social cups and Novel Object A/B on slow vertical, horizontal and diagonal gestures. The marker should no longer jump on initial touch, should follow, and should not scroll the page while held.
4. Use Reset Handles, verify centered thirds and marker defaults; test width slider independently.
5. Save/re-open existing and new sessions, verify backwards-compatible loading and exported data.
6. Review on real iPhone and iPad (portrait/landscape when available), in both Chinese and English, with and without pose analysis.

Xcode / iOS SDK and actual phone build verification were **not available** in this environment. App Store and model licensing checks in RELEASE_CHECKLIST.md still apply.
