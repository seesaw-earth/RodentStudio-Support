# RodentStudio 0.6.0

Renamed from Rodent Desktop Native. Built without a macOS SDK: Swift syntax and the Xcode project file
were checked; the app has **not** been compiled or run.

## Name

- App, Xcode project (`RodentStudio.xcodeproj`), target, source folder (`RodentStudio/`), window title and
  the app label written into exports are RodentStudio. The bundle identifier and the workspace folder
  (`~/Library/Containers/…/Application Support/RodentDesktopNative`) are unchanged, so existing workspaces
  and tracking runs open as before.

## Data organized as Task → Group → Animal → Session

- The sidebar is the data: task, group (only when groups are used), animal, session (recording date ·
  session number). Task, group and animal open overview pages; a session opens the guided steps.
- Every video is one session of one animal. Adding videos opens a sheet in which animal ID, recording
  date and session number (实验次数) are required (prefilled from the file name / file date and the next
  free session number); group and sex belong to the animal and are kept for animals that already have
  sessions. A duplicate animal + session number is refused.
- New “Session info” step (replaces “Video & animal”): animal, group and sex (applied to all sessions of the
  animal), date, session number, phase / day / trial as in the original apps, notes, exclusion with reason.
- Analysis requires complete session information; sessions imported by earlier versions are marked and
  can be completed in Session info.
- “New task” and “Add videos” in the sidebar toolbar; adding from a group or animal presets them.
- Animal and group pages can rename an animal (merging into an existing animal only without session
  number clashes) or a group.

## Results, summaries and group comparison

- One computation path for a session's numbers (`SessionResultsEngine`), used by the Results tab, the
  summaries and the exports. Summaries are saved next to each run with a SHA-256 key of everything they
  depend on and recomputed when any input changes.
- Task page: all sessions (date, session number, phase, analysis, primary measure, tracking check,
  inclusion), group comparison, export. Group page: animals, descriptive summary per phase, group-level
  export. Animal page: sessions and one measure across session numbers.
- Group comparison ported from RodentFlow 1.3 (GroupAnalysis + StatsEngine) and generalized to RodentPose,
  RodentLimb and RodentFlow: between groups, across session numbers (new), across days, time course,
  paired measures, change between phases; parametric / non-parametric; all pairs / vs first group;
  optional test against a reference value. n = animals; phases never pooled by default; excluded sessions
  left out; preliminary, uncorrected across measures.
- Task-level and group-level exports: sessions.csv, metrics_long.csv, metrics_wide.csv, animals.csv,
  group_summary.csv, README_methods.txt. Comparison export: figure PNG, summary TXT, result JSON, animal
  values CSV. All English with the original IDs. See DATA_PROCESSING_CN.md.

## Review

- The Quick check tab is removed. Its tracking check (range, default frames 0–99; viewed and flagged frames;
  verdict; notes) is now part of “Frame review & export”, which has a Play button (⌥P) with speeds Every
  frame / 0.25× / 0.5× / 1× / 2× for short and long runs.
- RodentFlow sessions get a “Frame review & export” tab: centroid on the video, slider, step, play, tracking
  check and export of the centroid samples (CSV) with the check (JSON).
- Frame-review exports record session date, session number and exclusion.

## Data tab

- Date and Session columns replace Day and Trial; one row per session.
