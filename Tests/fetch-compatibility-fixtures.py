#!/usr/bin/env python3
"""Fetch optional, immutable public extension test fixtures from their authors."""
import hashlib,json,sys,urllib.request
from pathlib import Path
root=Path(__file__).resolve().parent
output=Path(sys.argv[1]) if len(sys.argv)>1 else root.parent/'.build/fixtures'
output.mkdir(parents=True,exist_ok=True)
for fixture in json.loads((root/'compatibility-fixtures.json').read_text()):
    data=urllib.request.urlopen(fixture['url'],timeout=30).read()
    if hashlib.sha256(data).hexdigest()!=fixture['sha256']:
        raise RuntimeError('Fixture checksum mismatch: '+fixture['file'])
    (output/fixture['file']).write_bytes(data)
    print('Fetched '+fixture['file']+' @ '+fixture['commit'])
