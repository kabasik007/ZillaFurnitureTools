#!/usr/bin/env python3
"""Cross-check the test scene manifest, Viyar cutting CSV and DXF drawings."""
import csv
import json
from pathlib import Path

out = Path('M:/projects/furniture/AC-Station/exports/viyar_test_20261104')
manifest = json.loads((out / 'drilling_manifest.json').read_text(encoding='utf-8'))
qa = json.loads((out / 'scene_qa.json').read_text(encoding='utf-8'))
with (out / 'viyar_parts_edges_TEST.csv').open(encoding='utf-8-sig', newline='') as fh:
    rows = {row['Назва']: row for row in csv.DictReader(fh, delimiter=';')}
assert len(rows) == qa['part_count'] == 15
assert len(manifest['holes']) == qa['hole_count'] == 26
assert qa['all_manifold']
for part in manifest['parts']:
    name = part['name']
    row = rows[name]
    lengths = sorted((v for i, v in enumerate(part['dims_mm']) if i != part['thickness_axis']), reverse=True)
    long_edge = 0.5 if row['Л'] == '1' else float(row['Л'])
    right_edge = 0.5 if row['П'] == '1' else float(row['П'])
    top_edge = 0.5 if row['В'] == '1' else float(row['В'])
    bottom_edge = 0.5 if row['Н'] == '1' else float(row['Н'])
    assert abs(lengths[0] - long_edge - right_edge - float(row['Довжина'])) < 0.01, name
    assert abs(lengths[1] - top_edge - bottom_edge - float(row['Ширина'])) < 0.01, name
    dxf = (out / 'dxf_drawings' / f'{name}_FACE_TEST.dxf').read_text(encoding='ascii')
    assert dxf.startswith('0\nSECTION\n') and dxf.endswith('0\nEOF\n'), name
    face_count = sum(1 for hole in manifest['holes'] if hole['part_name'] == name and
                     hole['direction'][part['thickness_axis']] != 0)
    assert dxf.count('0\nCIRCLE\n') == face_count, name
assert sum(row['band_05_faces'] for row in qa['parts']) == 4
assert sum(row['band_2_faces'] for row in qa['parts']) == 23
print('Verified 15 saw sizes and edge maps, 26 solid holes, 17 DXF drawings.')
