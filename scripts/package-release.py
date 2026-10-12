#!/usr/bin/env python3
"""Package a committed source tree and matching app for a GitHub release."""
import hashlib,json,plistlib,subprocess,sys,tempfile,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
version=sys.argv[1] if len(sys.argv)>1 else plistlib.loads((root/'Info.plist').read_bytes())['CFBundleShortVersionString']
app=root/'dist/Vela.app';output=root/'dist/releases';output.mkdir(parents=True,exist_ok=True)
assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']==version
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
appzip=output/f'Vela-{version}-macOS.zip';sourcezip=output/f'Vela-{version}-source.zip'
subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(appzip)],check=True)
with tempfile.TemporaryDirectory(prefix='vela-package-') as temporary:
 clean=Path(temporary)/'app.zip'
 with zipfile.ZipFile(appzip) as original,zipfile.ZipFile(clean,'w') as archive:
  for item in original.infolist():
   if item.filename not in ['__MACOSX/._Vela.app','Vela.app/.DS_Store','Vela.app/._.DS_Store']:archive.writestr(item,original.read(item.filename))
 clean.replace(appzip)
 subprocess.run(['ditto','-x','-k',str(appzip),temporary],check=True)
 extracted=Path(temporary)/'Vela.app'
 subprocess.run(['xattr','-d','com.apple.FinderInfo',str(extracted)],capture_output=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(extracted)],check=True)
subprocess.run(['git','archive','--format=zip','--prefix=Vela/','HEAD','-o',str(sourcezip)],cwd=root,check=True)
results=root/'.build/fixtures/results.json'
if results.exists():
 checks=json.loads(results.read_text());assert all(checks.values());(output/'engine-test-results.json').write_text(json.dumps(checks,indent=2,sort_keys=True))
checksums=''.join(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.name+'\n' for file in sorted(output.iterdir()) if file.is_file() and file.name!='SHA256SUMS')
(output/'SHA256SUMS').write_text(checksums)
print('Packaged',appzip,sourcezip)
