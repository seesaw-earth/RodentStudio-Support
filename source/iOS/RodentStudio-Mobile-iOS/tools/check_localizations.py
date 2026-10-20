#!/usr/bin/env python3
"""Offline localization integrity check for RodentPose (Python 3, no packages needed)."""
from pathlib import Path
import json,re,sys
root=Path(__file__).resolve().parents[1]
app=root/'RodentPose'
cat=json.loads((app/'Localizable.xcstrings').read_text())
patterns=json.loads((app/'L10nPatterns.json').read_text())
errors=[]
for key,entry in cat['strings'].items():
    loc=entry.get('localizations',{})
    for language in ('en','zh-Hans'):
        val=loc.get(language,{}).get('stringUnit',{}).get('value')
        if not val: errors.append(f'No {language} translation: {key}')
        if language=='en' and val and re.search('[\u3400-\u9fff]',val): errors.append(f'Untranslated English: {key}')
for pattern in patterns:
    try: rx=re.compile(pattern['regex'])
    except re.error as e: errors.append(f'Invalid regex {pattern["source"]}: {e}');continue
    source=pattern['source']
    sample=re.sub(r'\{\d+\}','SAMPLE',source)
    m=rx.fullmatch(sample)
    if not m:errors.append(f'Pattern cannot match sample: {source}')
    for i in range(rx.groups):
        if '{'+str(i)+'}' not in pattern['translation']:
            errors.append(f'Missing English placeholder {i}: {source}')
    if re.search('[\u3400-\u9fff]',pattern['translation']):
        errors.append(f'Untranslated dynamic English: {source}')
if not (app/'Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png').exists():errors.append('Missing App Icon')
if not (app/'MousePose6_960_int8.mlpackage/Data/com.apple.CoreML/weights/weight.bin').exists():errors.append('Missing Core ML weights')
pbx=(root/'RodentPose.xcodeproj/project.pbxproj').read_text()
for token in ['com.ziqingshi.rodentpose', 'RodentPose.app','MARKETING_VERSION = 1.0;']:
    if token not in pbx: errors.append('Missing project setting: '+token)
for old in ['RodentFlowLab','RodentFlow Lab','rodentflowlab']:
    if old in pbx: errors.append('Old brand in project: '+old)
print(f'Localization check: {len(cat["strings"])} static keys, {len(patterns)} interpolated keys; {len(errors)} issues')
if errors:
    print('\n'.join(errors[:40]));sys.exit(1)
