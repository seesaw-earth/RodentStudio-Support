#!/usr/bin/env bash
# Quick checks on a Mac with Xcode command-line tools. This is NOT a full app build (use ⌘B in Xcode).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/RodentStudio"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="$(uname -m)-apple-macos14.0"
SWIFTC=(xcrun --sdk macosx swiftc -typecheck -sdk "$SDK" -target "$TARGET" -swift-version 5)

# 1. Original RodentLimb analyzers.
"${SWIFTC[@]}" Analysis/*.swift
# 2. Statistics: RodentFlow 1.3 StatsEngine port (no app types).
"${SWIFTC[@]}" Core/StatsEngine.swift
# 3. Every source file of the app together (type errors of all views at once; still not a build:
#    no Core ML model compilation, no signing, no resources). The model layer (session model, group
#    analysis, session metrics) depends on the analyzers of all three modules, so it is checked here.
SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find . -name '*.swift' | sort)
"${SWIFTC[@]}" "${SOURCES[@]}"
# 4. Resources the analyzers need at run time.
for r in Resources/EnglishTranslations.json Resources/L10nPatterns.json Resources/RodentFlowChinese.json; do
  plutil -lint -s "$r" >/dev/null 2>&1 || python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$r"
done
plutil -lint "$ROOT/RodentStudio.xcodeproj/project.pbxproj"
echo 'PASS: analyzers, statistics and all sources type-check; resources and Xcode project parse (not a macOS app build).'
