#!/usr/bin/env python3
"""Validate the exported Viyar review package before a manual import trial."""
from __future__ import annotations

import csv
import json
import sys
from collections import Counter
from pathlib import Path


def verify(folder: Path) -> str:
    manifest = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
    missing = [name for name in manifest['files'] if not (folder / name).is_file()]
    if missing:
        raise ValueError(f'Missing files: {missing}')
    with (folder / '01_parts_edges_viyar.csv').open(encoding='utf-8-sig', newline='') as stream:
        parts = list(csv.reader(stream, delimiter=';'))
    if len(parts) != manifest['parts_with_edge_plan']:
        raise ValueError('Part count differs from manifest')
    names = []
    for row in parts:
        if len(row) != 10 or not all(float(row[i]) > 0 for i in (0, 1, 2)):
            raise ValueError(f'Invalid part dimensions/columns: {row}')
        if not all(row[i] in {'0', '1', '2'} for i in range(3, 7)):
            raise ValueError(f'Invalid edge code: {row}')
        edge_mm = (0.0, 0.5, 2.0)
        effective_length = float(row[0]) - edge_mm[int(row[5])] - edge_mm[int(row[6])]
        effective_width = float(row[1]) - edge_mm[int(row[3])] - edge_mm[int(row[4])]
        if min(effective_length, effective_width) < 50:
            raise ValueError(f'Viyar minimum 50 mm after edge allowance: {row[8]}')
        names.append(row[8])
    if any(count > 1 for count in Counter(names).values()):
        raise ValueError('Repeated part names need manual identity review')
    with (folder / '03_drilling_review.csv').open(encoding='utf-8', newline='') as stream:
        holes = list(csv.DictReader(stream, delimiter=';'))
    if len(holes) != manifest['recorded_physical_holes']:
        raise ValueError('Hole count differs from manifest')
    for hole in holes:
        if hole['part_name'] not in names:
            raise ValueError(f'Hole has no exported part: {hole["part_name"]}')
        if not 0 < float(hole['diameter_mm']) <= 35 or float(hole['depth_mm']) <= 0:
            raise ValueError(f'Invalid hole: {hole}')
    if manifest['format'] == 'Viyar_saw_CSV_only' and '02_ABF_flatten_viyar.dxf' in manifest['files']:
        raise ValueError('CSV-only package mislabeled as ABF DXF')
    if '05_batch_face_drilling_TRIAL.dxf' in manifest['files']:
        dxf = (folder / '05_batch_face_drilling_TRIAL.dxf').read_text(encoding='utf-8').splitlines()
        if len(dxf) % 2:
            raise ValueError('Odd DXF group-code/value line count')
        pairs = list(zip(dxf[::2], dxf[1::2]))
        entities = Counter(value for code, value in pairs if code == '0')
        trial = manifest['trial_dxf']
        if entities['LWPOLYLINE'] != trial['parts'] or entities['CIRCLE'] != trial['face_holes']:
            raise ValueError('DXF contour/hole count differs from manifest')
        if ('9', '$INSUNITS') not in pairs or ('70', '4') not in pairs or pairs[-1] != ('0', 'EOF'):
            raise ValueError('DXF header, millimetre unit, or terminator missing')
    return f'PASS: {len(parts)} parts, {len(holes)} recorded holes, {len(manifest["files"])} files'


if __name__ == '__main__':
    print(verify(Path(sys.argv[1])))
