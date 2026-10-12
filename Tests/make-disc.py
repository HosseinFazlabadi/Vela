from pathlib import Path
import subprocess
import sys
r=Path(sys.argv[1]).resolve();out=r/'test-dvd';import shutil
shutil.rmtree(out,ignore_errors=True);out.mkdir(exist_ok=True)
subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(r/'test.mp4'),'-target','pal-dvd','-c:a','ac3',str(r/'dvd-title.mpg')],check=True)
xml=f'''<dvdauthor dest="{out}"><vmgm><menus><video format="pal"/><pgc><pre>jump titleset 1 menu;</pre></pgc></menus></vmgm><titleset><menus><video format="pal"/><pgc entry="root"><pre>jump title 1;</pre></pgc></menus><titles><video format="pal"/><audio format="ac3"/><pgc><vob file="{r/'dvd-title.mpg'}" chapters="0,00:00:05"/></pgc><pgc><vob file="{r/'dvd-title.mpg'}" chapters="0,00:00:05"/></pgc></titles></titleset></dvdauthor>'''
(r/'dvd.xml').write_text(xml)
subprocess.run(['dvdauthor','-x',str(r/'dvd.xml')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
print('Authored DVD fixture with 2 titles and chapters')
