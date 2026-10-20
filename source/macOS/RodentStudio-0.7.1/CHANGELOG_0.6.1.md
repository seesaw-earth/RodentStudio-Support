# RodentStudio 0.6.1 — Task management

- Add editable task notes to the sidebar and task overview, persisted as an optional workspace JSON field.
- Add confirmed deletion of a task and its imported session records, without deleting media or tracking-run directories. Active runs must be paused.
- Consolidate same-name, same-assay tasks with identical notes (including two empty notes), preserving source session IDs, saved run folders and surviving group styles. Distinct notes keep tasks independent.
- Block automatic consolidation when it would introduce duplicate session numbers or contradictory nonempty group/sex metadata for an animal.
- Back up the prior workspace before initial automatic migration and before any note edit that joins tasks, using UUID-suffixed JSON backups.
- Allow users to create a same-name task with another note. If that note already exists for the same name and assay, select the existing task instead of duplicating it.
- Improve `install_models.py` to reuse the two original `.mlpackage` bundles from the previous 0.6.0 installation and skip source search when destination models already exist.
- Change corrupted Unicode legacy README archive filenames to ASCII-only equivalents for compatibility with macOS `unzip`.

Validation: Swift parser and PBX project lint passed on Linux; 18 standalone merge assertions passed. No macOS SDK in this environment; Xcode build and UI use remain untested.
