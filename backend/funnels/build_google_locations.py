"""Rebuild the pinned Google location reference without network access.

Source: https://developers.google.com/google-ads/api/data/geotargets
CSV: https://developers.google.com/static/google-ads/api/data/geo/geotargets-2026-08-12.csv.zip
Google Developers reference data, CC BY 4.0 unless otherwise noted by Google.
Usage: python3 backend/funnels/build_google_locations.py /path/to/geotargets.zip
Only Active cities and selected administrative region types are included.
Canonical names are retained verbatim; no coordinates or hierarchy are inferred.
"""
import csv
import gzip
import hashlib
import io
import json
import re
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1] / 'funnels'
SHA = 'd4a62971cb283e405a07d537a0af400816ff5a36283e60376a51c7657f3d1e89'
TYPES = ['City', 'State', 'Province', 'Region', 'Department', 'Canton',
         'Governorate', 'Prefecture', 'Autonomous Community', 'Division',
         'Territory', 'Union Territory', 'Okrug']
source = Path(sys.argv[1]).read_bytes()
assert hashlib.sha256(source).hexdigest() == SHA, 'Reference archive checksum mismatch'
countries = {r['code'] for r in json.loads((ROOT / 'google_targeting_catalog.json').read_text())['countries']}
archive = zipfile.ZipFile(io.BytesIO(source))
rows = []
for row in csv.DictReader(io.TextIOWrapper(archive.open(archive.namelist()[0]), encoding='utf-8-sig')):
    if row['Status'] == 'Active' and row['Target Type'] in TYPES and row['Country Code'] in countries:
        rows.append([row['Criteria ID'], row['Canonical Name'], row['Country Code'], row['Target Type']])
for ident, name, country, kind in rows:
    assert re.fullmatch(r'[1-9][0-9]{0,9}', ident) and 1 <= len(name) <= 300
    assert name == name.strip() and not re.search(r'[\x00-\x1f\x7f-\x9f<>\u2028\u2029]', name)
rows.sort(key=lambda r: int(r[0]))
assert len({r[0] for r in rows}) == len(rows)
data = {'version': 'google-locations-2026-08-12', 'source_sha256': SHA, 'types': TYPES, 'rows': rows}
raw = (json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
compressed = gzip.compress(raw, mtime=0)
(ROOT / 'google_locations_catalog.json.gz').write_bytes(compressed)
print(json.dumps({'locations': len(rows), 'countries': len({r[2] for r in rows}), 'json_bytes': len(raw), 'gzip_bytes': len(compressed), 'sha256': hashlib.sha256(compressed).hexdigest()}))
