#!/usr/bin/env python3
"""Static integration checks (not a macOS Xcode build or scientific accuracy validation)."""
from pathlib import Path
import re
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
core = root / 'RodentStudio'
pbx = (root / 'RodentStudio.xcodeproj/project.pbxproj').read_text()
failed=[]
def assert_contains(rel, *terms):
    s=(core/rel).read_text()
    for t in terms:
        if t not in s: failed.append(f'{rel}: missing {t}')
def assert_absent(rel, *terms):
    s=(core/rel).read_text()
    for t in terms:
        if t in s: failed.append(f'{rel}: unexpected {t}')
assert_contains('Core/WorkspaceStore.swift','struct TSTChamberReference','func registerTSTRecording','var tstChamber: TSTChamberReference?')
assert_contains('TSTMulti/TSTTaskWorkspaceView.swift','struct TSTRecordingAnalysisSheet','store.registerTSTRecording','SessionDate','TSTTaskArchive.sourceURL','TSTSessionStepView')
assert_contains('Core/TaskDataModel.swift','if assay == .tstMultiChamber','TSTSessionMetrics.load')
assert_contains('Views/AnalysisWorkflowView.swift','TaskOverviewView(experiment: exp','TSTRecordingAnalysisSheet(experiment: exp','TSTSessionStepView(video: video','TSTVideoPicker.choose()')
assert_absent('Views/AnalysisWorkflowView.swift','TSTTaskWorkspaceView(experiment: exp)')
assert_contains('TSTMulti/TSTTaskWorkspaceView.swift','keyboardShortcut(.cancelAction)','keyboardShortcut(.defaultAction)','model.errorMessage','isSkipped')
assert_contains('TSTMulti/Model/AppModel.swift','var resultMatchesSetup','private func remapScan()')
assert_contains('TSTMulti/TSTSessionMetrics.swift','tst_immobile_s','tst_no_mouse_pct','tst_bouts')
assert_contains('Core/TaskDataExport.swift','TaskDataModel','writeSessions','writeAnimals','writeGroupSummary')
if pbx.count('TSTSessionMetrics.swift in Sources') != 1: failed.append('Xcode target does not compile TSTSessionMetrics exactly once')
if pbx.count('MARKETING_VERSION = 0.7.1;') != 2: failed.append('Version mismatch')
if 'com.example.RodentDesktopNative' not in pbx: failed.append('Expected placeholder bundle id missing; check release settings manually')
files=list(core.rglob('*.swift'))
collisions={x.name for x in files if sum(y.name==x.name for y in files)>1}
if collisions: failed.append('Duplicate Swift basenames: '+str(collisions))
for f in files:
    if f.name not in pbx:
        failed.append('Swift file not referenced by project: '+str(f.relative_to(root)))
if failed:
    print('FAILED: '+ '\n'.join(failed)); sys.exit(1)
print(f'Static integration checks PASS: {len(files)} Swift files, task/data/view/metrics wiring, project references')
if sys.platform=='darwin':
    print('For macOS full build run: xcodebuild -project RodentStudio.xcodeproj -scheme RodentStudio -configuration Debug -destination platform=macOS build')
