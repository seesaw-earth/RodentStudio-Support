#!/usr/bin/env python3
"""Regression check for app-level SwiftUI dependency injection."""
from pathlib import Path

app = Path(__file__).resolve().parents[1] / 'RodentPose' / 'RodentPoseApp.swift'
settings = Path(__file__).resolve().parents[1] / 'RodentPose' / 'SettingsView.swift'
source = app.read_text()
sheet_content = source.split('.sheet(isPresented: $app.showSettings)', 1)[1].split('\n                }', 1)[0]
for dependency in ['app', 'app.store', 'app.engine']:
    assert f'.environmentObject({dependency})' in sheet_content, f'missing sheet injection: {dependency}'
    assert source.count(f'.environmentObject({dependency})') >= 2, f'missing root injection: {dependency}'
assert '@EnvironmentObject private var engine: PoseEngine' in settings.read_text()
assert source.index('.sheet(isPresented: $app.showSettings)') < source.rindex('.environmentObject(app.engine)')
print('Environment injection regression check: Settings sheet and root receive AppModel, SessionStore, PoseEngine')
