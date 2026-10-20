# SwiftUI settings crash fix

Observed on iOS: `SwiftUICore/EnvironmentObject.swift:93: Fatal error: No ObservableObject of type PoseEngine found.`

Cause: The in-app-language feature moved the Settings sheet to `RodentPoseApp` so that switching languages would not dismiss the sheet. However, `.environmentObject` modifiers remained **below** the `.sheet` modifier, and the separately hosted sheet was not guaranteed to inherit those objects.

Fix in `RodentPose/RodentPoseApp.swift`:
- Inject the same shared `app`, `app.store`, and `app.engine` directly into `SettingsView` in the `.sheet` closure.
- Move the root environment injections to **after** `.sheet` so its presentations and navigation inherit the same instances.
- Leave language selection, English-only scientific exports, calibration controls, and model files unchanged.

To verify on a real device or Simulator: launch the app; open **Settings**; change interface language among **中文 / English / Follow System**; close and reopen Settings; create an analysis and visit calibration; check export remains in English. Test on a device as the environment injection check is static, not an Xcode runtime test.

`numANECores` and `LaunchServices` diagnostic lines in the reported log are not the observed fatal exception; investigate them separately only if they persist as user-visible failures after resolving the `EnvironmentObject` crash.
