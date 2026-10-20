#!/usr/bin/env python3
"""RodentStudio 0.7.0 Build Fix 3 (macOS TST views).

Small, reversible source-only patch. Usage:
    python3 fix_rodentstudio_070_build3.py '/path/to/RodentStudio-0.7.0'

Applies to Build Fix 2 and can be run again safely. It never modifies model weights
or analytic algorithms. Creates *.buildfix3.bak before the first modification.
"""
from __future__ import annotations

import argparse
from pathlib import Path


def change(path: Path, edits: list[tuple[str, str]]) -> None:
    if not path.is_file():
        raise SystemExit(f"Missing Swift source: {path}")
    original = path.read_text(encoding="utf-8")
    updated = original
    for before, after in edits:
        if before in updated:
            count = updated.count(before)
            if count != 1:
                raise SystemExit(f"Expected 1 occurrence in {path}, found {count}: {before!r}")
            updated = updated.replace(before, after, 1)
        elif after not in updated:
            raise SystemExit(f"Unrecognized source contents; stopping without modifying {path}: {before!r}")
    if updated == original:
        print(f"ALREADY FIXED: {path.name}")
        return
    backup = path.with_name(path.name + ".buildfix3.bak")
    if not backup.exists():
        backup.write_text(original, encoding="utf-8")
    path.write_text(updated, encoding="utf-8")
    print(f"FIXED: {path.name} (backup: {backup.name})")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("project_root", type=Path, help="folder containing RodentStudio.xcodeproj")
    args = p.parse_args()
    root = args.project_root.expanduser().resolve()
    if not (root / "RodentStudio.xcodeproj" / "project.pbxproj").exists():
        raise SystemExit("This is not the Xcode project root (RodentStudio.xcodeproj missing).")
    views = root / "RodentStudio" / "TSTMulti" / "Views"
    # Fix the misspelled model property (ChamberSummary has 'bouts', not 'tstBouts').
    # Explicit identity helps SwiftUI select the collection initializer rather
    # than reporting misleading Binding<C> overload diagnostics.
    change(views / "ResultsView.swift", [
        ("ForEach(result.summaries) { s in", "ForEach(result.summaries, id: \\.chamber) { s in"),
        ('Text("\\(s.tstBouts)")', 'Text("\\(s.bouts)")'),
    ])
    # .secondarySystemBackground belongs to UIKit, not AppKit.
    change(views / "ScanView.swift", [
        ("import SwiftUI\n/// Step 3", "import SwiftUI\nimport AppKit\n/// Step 3"),
        ("ForEach(0..<layout.count, id: \\.self) { i in",
         "ForEach(Array(0..<layout.count), id: \\.self) { i in"),
        ("Color(.secondarySystemBackground)", "Color(nsColor: NSColor.controlBackgroundColor)"),
    ])
    print("DONE: TST view type errors patched. Clean Build Folder, then Command+B in Xcode.")


if __name__ == "__main__":
    main()
