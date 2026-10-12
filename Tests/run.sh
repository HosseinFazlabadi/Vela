#!/bin/bash
set -euo pipefail
SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$SOURCE_ROOT/.build/fixtures"
command -v ffmpeg >/dev/null || { echo 'ffmpeg is required to generate test media.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required for the local test server.' >&2; exit 1; }
python3 "$SOURCE_ROOT/Tests/make-fixtures.py" "$FIXTURES"
command -v dvdauthor >/dev/null || { echo "dvdauthor is required for the authored DVD fixture." >&2; exit 1; }
python3 "$SOURCE_ROOT/Tests/make-disc.py" "$FIXTURES"
cp "$SOURCE_ROOT/Tests/test-extension.lua" "$FIXTURES/test-extension.lua"
cp "$SOURCE_ROOT/Tests/api-contract.lua" "$FIXTURES/api-contract.lua"
cp "$SOURCE_ROOT/Tests/command-extension.lua" "$FIXTURES/command-extension.lua"
"$SOURCE_ROOT/build.sh"
xcrun clang -O2 -DLUA_USE_MACOSX -I "$SOURCE_ROOT/Vendor/lua-5.1.5/src" "$SOURCE_ROOT/Vendor/lua-5.1.5/src/luac.c" "$SOURCE_ROOT"/.build/lua/*.o -o "$SOURCE_ROOT/.build/luac"
printf '%s\n' 'function descriptor()return {title="Compiled Extension"}end' 'function activate()vlc.dialog("Compiled"):add_label("BYTECODE OK")end' > "$FIXTURES/compiled-extension.lua"
"$SOURCE_ROOT/.build/luac" -o "$FIXTURES/compiled-extension.luac" "$FIXTURES/compiled-extension.lua"

python3 -m http.server 18763 --bind 127.0.0.1 --directory "$FIXTURES" > "$SOURCE_ROOT/.build/http-test.log" 2>&1 &
VELA_HTTP_PID=$!
trap 'kill "$VELA_HTTP_PID" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$VELA_HTTP_PID" || { echo 'Test server did not start; check whether port 18763 is already in use.' >&2; exit 1; }
"${VELA_OUTPUT_DIR:-$SOURCE_ROOT/dist}/Vela.app/Contents/MacOS/Vela" --engine-test "$FIXTURES" > "$SOURCE_ROOT/.build/engine-test.log" 2>&1
python3 - "$FIXTURES/results.json" <<'PY'
import json,sys
checks=json.load(open(sys.argv[1]))
for name,success in checks.items(): print(('PASS ' if success else 'FAIL ')+name)
if not all(checks.values()): sys.exit(1)
print(f'{len(checks)}/{len(checks)} engine checks passed')
PY
ffprobe -v error -show_entries stream=codec_type,codec_name,start_time,duration:format=duration -of json "$FIXTURES/converted.mp4" > "$SOURCE_ROOT/.build/converted-probe.json"
python3 - "$SOURCE_ROOT/.build/converted-probe.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
assert {s['codec_type'] for s in result['streams']} == {'audio','video'}
assert 9 < float(result['format']['duration']) < 11
assert all(abs(float(s['start_time']))<0.5 for s in result['streams'])
print('PASS independent MP4 duration and start timestamps')
PY
ffmpeg -hide_banner -loglevel error -i "$FIXTURES/converted.mp4" -f null -
ffmpeg -hide_banner -loglevel error -xerror -i "$FIXTURES/recording.mkv" -f null -

ffmpeg -hide_banner -loglevel error -xerror -i "$FIXTURES/capture-recording.mkv" -f null -
ffmpeg -hide_banner -loglevel error -i "$FIXTURES/streaming.ts" -f null -

ffmpeg -hide_banner -loglevel error -xerror -i "$FIXTURES/converted.wav" -f null -

python3 - "$FIXTURES" <<'CAPTURE_CHECK'
import array,json,math,subprocess,sys
from pathlib import Path
fixtures=Path(sys.argv[1])
for name in ['capture-audio.mkv','capture-static.mkv','capture-streaming.mkv']:
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-xerror','-i',str(fixtures/name),'-f','null','-'],check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=codec_type,start_time,sample_rate,channels:format=duration','-of','json',str(fixtures/'capture-audio.mkv')]))
assert {s['codec_type'] for s in probe['streams']}=={'video','audio'}
assert 1.5<float(probe['format']['duration'])<3.5
assert max(float(s['start_time']) for s in probe['streams'])-min(float(s['start_time']) for s in probe['streams'])<0.15
samples=array.array('f',subprocess.check_output(['ffmpeg','-v','error','-i',str(fixtures/'capture-audio.mkv'),'-map','0:a:0','-f','f32le','-']))
assert samples and math.sqrt(sum(x*x for x in samples)/len(samples))>0.03
print('PASS independent captured audio signal, A/V start timestamps and static/live stream decode')
CAPTURE_CHECK
