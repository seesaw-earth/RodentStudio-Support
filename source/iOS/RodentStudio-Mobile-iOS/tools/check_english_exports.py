#!/usr/bin/env python3
"""Static guard and optional Swift runtime smoke test for English-only scientific output."""
from pathlib import Path
import json, re, shutil, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
app = root / 'RodentPose'
translations = json.loads((app/'EnglishTranslations.json').read_text())
xc = json.loads((app/'Localizable.xcstrings').read_text())['strings']
expected = {key:v['localizations']['en']['stringUnit']['value'] for key,v in xc.items() if v.get('localizations',{}).get('en',{}).get('stringUnit',{}).get('value')}
assert translations == expected, 'EnglishTranslations.json is stale: run tools/update_english_translations.py'
assert not any(re.search('[\u3400-\u9fff]',v) for v in translations.values())
patterns = json.loads((app/'L10nPatterns.json').read_text())
assert not any(re.search('[\u3400-\u9fff]',v['translation']) for v in patterns)
assert 'L10n.metricLabel(m.title, key: m.key)' in (app/'Export.swift').read_text()
assert 'L10n.reportText' in (app/'Export.swift').read_text()
assert 'var s = Exporter.englishSession(s)' in (app/'SessionStore.swift').read_text()
assert '.id(uiLanguage)' in (app/'RodentPoseApp.swift').read_text()
assert 'Picker(L10n.tr("界面语言")' in (app/'SettingsView.swift').read_text()
print('Static checks: catalog sync, source export policy, in-app picker OK')
if shutil.which('swiftc'):
    with tempfile.TemporaryDirectory(prefix='rodentpose_locale_') as tmp:
        work=Path(tmp)
        for name in ('EnglishTranslations.json','L10nPatterns.json'):
            shutil.copy(app/name,work/name)
        (work/'main.swift').write_text(r'''
import Foundation
struct Template: Decodable { let regex: String; let translation: String; let source: String }
func containsHan(_ s: String) -> Bool { s.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) } }
let examples = ["嗅探陌生鼠", "首次探索新物体", "陌生鼠嗅探次数", "鼻–鼻接触", "平均速度", "中箱", "圈", "箱室停留时间"]
for s in examples {
  let en = L10n.english(s)
  assert(!containsHan(en), "Not English: \(s) -> \(en)")
}
UserDefaults.standard.set("zh-Hans", forKey: L10n.preferenceKey)
assert(L10n.tr("平均速度") == "平均速度")
assert(L10n.metricLabel("平均速度", key: "mean_speed") == "Mean speed")
UserDefaults.standard.set("en", forKey: L10n.preferenceKey)
assert(L10n.tr("平均速度") == "Mean speed")
assert(L10n.metricLabel("未翻译的实验指标", key: "custom_metric") == "Custom Metric")
let source = try! Data(contentsOf: Bundle.main.url(forResource: "L10nPatterns", withExtension: "json")!)
let templates = try! JSONDecoder().decode([Template].self, from: source)
for p in templates {
  let test = p.source.replacingOccurrences(of: "\\{[0-9]+\\}", with: "TEST", options: .regularExpression)
  let result = L10n.english(test)
  assert(!containsHan(result), "Untranslated dynamic sample: \(test)")
}
print("Swift runtime: UI language, nested labels and \(templates.count) dynamic templates OK")
''')
        build=subprocess.run(['swiftc',str(app/'L10n.swift'),str(work/'main.swift'),'-o',str(work/'langtest')],capture_output=True,text=True)
        assert build.returncode==0,build.stderr
        proc=subprocess.run([str(work/'langtest')],capture_output=True,text=True,cwd=work)
        assert proc.returncode==0,proc.stdout+'\n'+proc.stderr
        print(proc.stdout.strip())
else: print('Swift compiler not found, runtime test skipped')
