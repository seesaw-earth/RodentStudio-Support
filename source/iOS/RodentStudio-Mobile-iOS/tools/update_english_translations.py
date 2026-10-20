#!/usr/bin/env python3
"""Refresh the runtime English catalog from Localizable.xcstrings."""
from pathlib import Path
import json
app = Path(__file__).resolve().parents[1] / "RodentPose"
entries = json.loads((app / "Localizable.xcstrings").read_text())["strings"]
translations = {k: v["localizations"]["en"]["stringUnit"]["value"] for k,v in entries.items()
                if v.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")}
(app / "EnglishTranslations.json").write_text(json.dumps(translations, ensure_ascii=False, sort_keys=True, indent=2)+"\n")
print(f"Wrote {len(translations)} English source-to-target translations")
