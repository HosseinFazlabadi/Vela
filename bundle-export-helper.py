#!/usr/bin/env python3
import sys,subprocess,shutil,json,re
from pathlib import Path
source=Path(shutil.which('ffmpeg') or '').resolve();dest=Path(sys.argv[1]);dest.mkdir(parents=True,exist_ok=True)
if not source.is_file():raise SystemExit('ffmpeg is required to build the bundled export helper.')
pending=[source];seen={};minimum=(14,0)
while pending:
 p=pending.pop().resolve()
 if p in seen:continue
 deps=[]
 for line in subprocess.check_output(['otool','-L',str(p)],text=True).splitlines()[1:]:
  value=line.strip().split(' (')[0]
  if value.startswith('/opt/homebrew/') or value.startswith('/usr/local/'):
   lib=Path(value).resolve()
   if lib!=p:deps.append((value,lib));pending.append(lib)
 seen[p]=deps
 build=subprocess.check_output(['vtool','-show-build',str(p)],text=True)
 for value in re.findall(r'minos ([\d.]+)',build):minimum=max(minimum,tuple(map(int,value.split('.'))))
for p in seen:shutil.copy2(p,dest/p.name)
for p,deps in seen.items():
 target=dest/p.name
 subprocess.run(['chmod','u+w',str(target)],check=True)
 args=['install_name_tool']
 if p.suffix=='.dylib':args+=['-id','@loader_path/'+p.name]
 for old,lib in deps:args+=['-change',old,'@loader_path/'+lib.name]
 if len(args)>1:subprocess.run(args+[str(target)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 subprocess.run(['codesign','--force','--sign','-',str(target)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
licenses=dest/'Notices';licenses.mkdir(exist_ok=True)
formulae={}
for p in seen:
 parts=p.parts
 if 'Cellar' not in parts:continue
 i=parts.index('Cellar');prefix=Path(*parts[:i+3]);formula=parts[i+1];formulae[formula]=parts[i+2]
 notice=licenses/formula;notice.mkdir(exist_ok=True)
 for pattern in ['LICENSE*','COPYING*','share/doc/**/LICENSE*','share/doc/**/COPYING*','.brew/*.rb']:
  for file in prefix.glob(pattern):
   if file.is_file():shutil.copy2(file,notice/file.name)
for license_file in Path(__file__).parent.glob('COPYING-*.txt'):shutil.copy2(license_file,licenses/license_file.name)
manifest={'helper':'FFmpeg','version':subprocess.check_output([str(source),'-version'],text=True).splitlines()[0],'minimum_macos':'.'.join(map(str,minimum)),'libraries':[p.name for p in seen],'formulae':formulae}
(dest/'manifest.json').write_text(json.dumps(manifest,indent=2))
print('Bundled export helper:',len(seen),'binaries; minimum macOS',manifest['minimum_macos'])
