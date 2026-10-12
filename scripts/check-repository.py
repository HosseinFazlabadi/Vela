#!/usr/bin/env python3
"""Check source metadata, asset references and accidental private files."""
import ast,json,plistlib,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
required=['README.md','LICENSE.txt','COPYING-GPL3.txt','THIRD-PARTY-NOTICES.md','CONTRIBUTING.md','SECURITY.md','CODE_OF_CONDUCT.md','CHANGELOG.md']
for name in required:assert (root/name).is_file(),name
info=plistlib.loads((root/'Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='local.vela.player'
assert info['LSMinimumSystemVersion']=='26.0'
assert json.loads((root/'extension-api-inventory.json').read_text())['upstream_function_count']==144
for folder in (root/'Assets.xcassets').glob('*.appiconset'):
 for image in json.loads((folder/'Contents.json').read_text()).get('images',[]):
  if image.get('filename'):assert (folder/image['filename']).is_file(),image['filename']
for file in root.rglob('*'):
 if not file.is_file() or any(x in file.relative_to(root).parts for x in ['.git','.build','dist','__pycache__']):continue
 assert file.suffix not in ['.p12','.p8','.key'],str(file)
 if file.suffix=='.py':ast.parse(file.read_text(),filename=str(file))
 if file.suffix in ['.swift','.py','.sh','.md','.json','.yml'] and 'Vendor' not in file.parts:
  text=file.read_text()
  assert not re.search('/'+'Users/'+r'[^/\s]+/',text),str(file)
  assert not re.search(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',text),str(file)
print('Repository metadata, sources and asset references passed')
