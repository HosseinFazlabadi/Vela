import pathlib,subprocess,concurrent.futures
import sys
out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
def run(args): subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*args],check=True)
run(['-f','lavfi','-i','testsrc2=size=640x360:rate=24','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','10','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',str(out/'test.mp4')])
(out/'embedded.srt').write_text('1\n00:00:00,000 --> 00:00:09,000\nVela subtitle verification\n')
(out/'external.srt').write_text('1\n00:00:00,000 --> 00:00:09,000\nExternal subtitle verification\n')
(out/'chapters.txt').write_text(';FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=5000\ntitle=First chapter\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=5000\nEND=10000\ntitle=Second chapter\n')
run(['-i',str(out/'test.mp4'),'-i',str(out/'embedded.srt'),'-f','ffmetadata','-i',str(out/'chapters.txt'),'-map','0:v','-map','0:a','-map','0:a','-map','1:0','-map_metadata','2','-c','copy','-metadata:s:a:0','language=eng','-metadata:s:a:1','language=jpn',str(out/'test.mkv')])
def make(spec):
 ext,opts=spec
 run(['-i',str(out/'test.mp4'),*opts,str(out/('test.'+ext))])
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as p:
 list(p.map(make,[('webm',['-c:v','libvpx-vp9','-deadline','realtime','-cpu-used','8','-c:a','libopus']),('avi',['-c:v','mpeg4','-c:a','libmp3lame']),('wav',['-vn','-c:a','pcm_s16le']),('flac',['-vn','-c:a','flac']),('mp3',['-vn','-c:a','libmp3lame']),('ogg',['-vn','-ac','2','-c:a','vorbis','-strict','experimental'])]))
print('Created 8 media fixtures, subtitles, and chapters')

run(['-i',str(out/'test.mp4'),'-c','copy','-movflags','+faststart',str(out/'network.mp4')])

import zipfile
with zipfile.ZipFile(out/'test-package.vle','w') as z:
 z.writestr('script.lua',"function descriptor()return {title='Packaged Module'}end\nfunction activate()local helper=require('helper');vlc.dialog('Package'):add_label(helper.message)end")
 z.writestr('modules/helper.lua',"return {message='PACKAGE OK'}")
with zipfile.ZipFile(out/'unsafe-package.vle','w') as z:
 z.writestr('../outside.lua','bad')
 z.writestr('script.lua','function descriptor()return {}end')
(out/'trigger-extension.lua').write_text("function descriptor()return {title='Trigger',capabilities={'trigger'}}end\nfunction trigger()vlc.dialog('Trigger'):add_label('TRIGGER OK')end\nfunction activate()error('Wrong lifecycle')end")

(out/'blocked-extension.lua').write_text("function descriptor()return {title='Blocked poll'}end\nfunction activate()local d=vlc.dialog('Blocked');d:add_label('POLL WAIT');d:update();vlc.net.poll({})end")
(out/'busy-extension.lua').write_text("function descriptor()return {title='Busy loop'}end\nfunction activate()local d=vlc.dialog('Busy');d:add_label('LOOP WAIT');d:update();while true do end end")

(out/'podcast.xml').write_text('<?xml version="1.0"?><rss version="2.0"><channel><title>Vela fixture feed</title><link>http://127.0.0.1:18763</link><description>Local test</description><item><title>Fixture episode</title><enclosure url="http://127.0.0.1:18763/test.mp4" length="1000" type="video/mp4"/></item></channel></rss>')
