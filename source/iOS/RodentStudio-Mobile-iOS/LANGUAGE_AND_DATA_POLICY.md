# RodentPose localization and research data policy

- **Settings > Language > Follow System / 中文 / English** immediately changes the interface without changing the iPhone system language. The selection is saved in `UserDefaults` (`uiLanguage`). `RodentPoseApp` rebuilds the underlying root view while retaining the settings sheet.
- `L10n.tr` is for interface strings; `L10n.english`, `L10n.metricLabel`, `L10n.reportText` are for generated scientific exports and saved metric metadata, independent of UI locale.
- CSV schema keys, frame columns, paradigm IDs, phase codes, metric descriptions, generated methods/warnings, JSON report fields and plain-text summaries are **English-only**. `SessionStore.save` also canonicalizes cached generated metric labels.
- **Researcher-entered values** (subject ID, group name, free-text notes, imported video name) are kept exactly as entered. Type these in English if you also require their contents to be English; silently translating labels can corrupt IDs.
- Old session files are converted when saved again, and old cached summary metric labels are normalized when exported. No migration or deletion of older sessions is performed on launch.
- Update `Localizable.xcstrings`, then run `python3 tools/update_english_translations.py` to regenerate `EnglishTranslations.json`; run `tools/check_localizations.py` and `tools/check_english_exports.py` before release.
- This is a source-level update. Complete build/test in Xcode on an iPhone to validate the picker and output for representative experiments, particularly methods templates containing interpolation.
