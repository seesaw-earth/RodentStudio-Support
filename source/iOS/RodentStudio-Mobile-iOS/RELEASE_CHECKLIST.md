# RodentPose — 双语发布检查清单 / Bilingual release checklist

> Status: **NOT ready for App Store release** until the items marked [ ] are completed and signed off by the maintainer.
>
> 状态：未完成打勾前请勿向 App Store 正式提交。

## A. Xcode / 工程

- [x] App / project / target / display name changed to **RodentPose**.
- [x] Bundle ID set to `com.ziqingshi.RodentStudio`; marketing version **1.0**, build **1**.
- [x] Keep `MousePose6_960_int8` as the model resource name to preserve loader compatibility.
- [x] English and 简体中文 localization resources and native app icon included.
- [ ] Confirm the Bundle ID is registered under your Apple Developer account and signing team is correct.
- [ ] Use **Xcode 26+ / iOS 26 SDK+** for App Store upload (per Apple requirements effective Apr 28, 2026).
- [ ] Build and run a **Debug** build on physical iPhone; verify model loads.
- [ ] Archive **Release** build, run validation, and upload via Xcode Organizer.

## B. 双语和功能测试 / Localization & functionality

- [ ] Test **Settings → Language → Follow System / 中文 / English**, including changing languages without closing Settings; capture catalog, calibration, analysis, export and error screens.
- [ ] Check long English titles on smaller iPhones and landscape iPad.
- [ ] Test all four demos: Open Field, Novel Object Recognition, Elevated Plus Maze, Three-Chamber.
- [ ] Verify from Photos and Files; foreground/background pause; storage; deleting video only.
- [ ] Validate English vs Chinese results generate **identical numeric metrics**, stable enum IDs, **identical English-only CSV metric labels, JSON description/method strings, cached session metric labels, and text summaries**. Preserve free-form user entries.
- [ ] Check two-animal identity continuity when mice overlap, and review frame alignment.
- [ ] Compare behavior scores against human annotations; disclose error bounds in public research claims.

## B2. 界面优化验收 / UX refresh checks (see `UX_REFRESH_NOTES.md`)

- [ ] Light, dark and **Increase Contrast**; Dynamic Type up to accessibility sizes on Info, Results and the step bar.
- [ ] Calibration magnifier, grab haptic, handle legend; dragging never scrolls the page; VoiceOver “Move left/right/up/down” actions.
- [ ] Results section links; figure menu (copy image, share image, copy English CSV); chart scrubbing; heat-map scale.
- [ ] Review Previous / Next event with and without a behavior filter.
- [ ] Session bars on iOS 26 (scroll-edge effect) and on iOS 17/18 (bar material).
- [ ] Home “Continue where you left off” and thumbnails; Data long-press menu.

## C. 开源合规 / Open-source compliance

- [x] App-source license text provided (GNU AGPL-3.0).
- [ ] Confirm rights from all code contributors and any institutional obligations before relicensing.
- [ ] Verify `ultralytics/yolo-ios-app` / UltralyticsYOLO version and downstream AGPL / App Store distribution compatibility with legal counsel/licensor as needed.
- [ ] Document source, preprocessing, licenses and right to redistribute the **included YOLO/Core ML weights**.
- [ ] Confirm training datasets permit model/weights redistribution and public examples; redact subject/institution information.
- [ ] Publish matching public source, build instructions, copyright notices, license and third-party attributions.
- [ ] If weights cannot legally be redistributed, do not publish/release the bundled weights until licensing is resolved.

## D. App Store Connect / 上架

- [ ] Apps → **+ → New App** (NOT New App Bundle); set primary language **English (U.S.)**, add **Chinese (Simplified)** metadata.
- [ ] Set category **Utilities**, price **Free**, age rating questionnaire, country availability and required compliance declarations.
- [ ] Paste localized names, subtitle, keywords, descriptions from `AppStore/` (verify marketing claims against device behavior).
- [ ] Create **real screenshots** for at least an iPhone with Dynamic Island (medium) and iPad **13-inch**, because this target includes iPad. No transparency; 1–10 screenshots per required display size. Localize text in screenshots.
- [ ] Screenshot plan: (1) home + pose, (2) Open Field, (3) Novel Object Recognition, (4) EPM, (5) Three-Chamber, (6) results/export. **Do not fabricate product UI screenshots.**
- [ ] Provide a reachable **Support URL**, **Privacy Policy URL** and support contact. Publish the reviewed policy, not the placeholder draft.
- [ ] Verify App Privacy answers using code + **third-party SDK** auditing. “Data Not Collected” may be chosen *only if true*.
- [ ] Verify encryption/export compliance, content rights and geographic availability.
- [ ] Provide review video and reviewer instructions; avoid example videos whose rights or privacy are unclear.
- [ ] Upload TestFlight build → internal testing → external testing → submit to App Review.

## E. 首发后 / Post-release

- [ ] Add the verified App Store link, release tag and model card to GitHub README.
- [ ] Publish issue templates, reproducibility figures, validation benchmarks and known limitations.
- [ ] Record public release version, model hash, 1–2 demo clips and tested iOS versions.

## Apple official references / 官方参考

- Xcode 26 SDK requirement: https://developer.apple.com/news/upcoming-requirements/
- Localization: https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
- Localized store metadata: https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/
- Required screenshots: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Review guidelines: https://developer.apple.com/app-store/review/guidelines/
- App privacy: https://developer.apple.com/app-store/app-privacy-details/
- Ultralytics licensing: https://www.ultralytics.com/license
