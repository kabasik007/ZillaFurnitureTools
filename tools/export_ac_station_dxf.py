#!/usr/bin/env python3
"""Make inspectable millimetre DXFs from the AC Station test manifest.

These are technical drawings, not a proven ViyarPro/ABF interchange file.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path('M:/projects/furniture/AC-Station')
OUT = ROOT / 'exports' / 'viyar_test_20261104'
manifest = json.loads((OUT / 'drilling_manifest.json').read_text(encoding='utf-8'))
assert manifest['status'] == 'TEST_ONLY_NOT_APPROVED_FOR_ORDER'
DXF_DIR = OUT / 'dxf_drawings'
DXF_DIR.mkdir(exist_ok=True)


def dxf(pairs: list[tuple[int, object]]) -> str:
    return ''.join(f'{code}\n{value}\n' for code, value in pairs)


def line(layer: str, a: tuple[float, float], b: tuple[float, float]) -> list[tuple[int, object]]:
    return [(0, 'LINE'), (8, layer), (10, round(a[0], 3)), (20, round(a[1], 3)),
            (30, 0), (11, round(b[0], 3)), (21, round(b[1], 3)), (31, 0)]


def circle(layer: str, x: float, y: float, diameter: float) -> list[tuple[int, object]]:
    return [(0, 'CIRCLE'), (8, layer), (10, round(x, 3)), (20, round(y, 3)),
            (30, 0), (40, round(diameter / 2, 3))]


def text(layer: str, x: float, y: float, label: str, height: float = 6) -> list[tuple[int, object]]:
    return [(0, 'TEXT'), (8, layer), (10, round(x, 3)), (20, round(y, 3)),
            (30, 0), (40, height), (1, label)]


def rect(layer: str, length: float, width: float) -> list[tuple[int, object]]:
    points = [(0, 0), (length, 0), (length, width), (0, width)]
    return sum((line(layer, points[i], points[(i + 1) % 4]) for i in range(4)), [])


def save_dxf(path: Path, entities: list[tuple[int, object]], layers: set[str]) -> None:
    header = [(0, 'SECTION'), (2, 'HEADER'), (9, '$ACADVER'), (1, 'AC1009'),
              (9, '$INSUNITS'), (70, 4), (0, 'ENDSEC'), (0, 'SECTION'), (2, 'TABLES'),
              (0, 'TABLE'), (2, 'LAYER'), (70, len(layers))]
    for name in sorted(layers):
        header += [(0, 'LAYER'), (2, name), (70, 0), (62, 7), (6, 'CONTINUOUS')]
    header += [(0, 'ENDTAB'), (0, 'ENDSEC'), (0, 'SECTION'), (2, 'ENTITIES')]
    path.write_text(dxf(header + entities + [(0, 'ENDSEC'), (0, 'EOF')]), encoding='ascii')


summary = []
for part in manifest['parts']:
    name = part['name']
    thin = part['thickness_axis']
    dimensions = part['dims_mm']
    long, short = sorted((axis for axis in range(3) if axis != thin), key=lambda axis: -dimensions[axis])
    length, width = dimensions[long], dimensions[short]
    holes = [hole for hole in manifest['holes'] if hole['part_name'] == name]
    entities = rect('OUTLINE', length, width)
    layers = {'OUTLINE', 'ANNOTATION'}
    face_holes = []
    edge_holes = []
    for hole in holes:
        axis = next(axis for axis, value in enumerate(hole['direction']) if value)
        if axis != thin:
            edge_holes.append(hole)
            continue
        layer = 'DEPTHF' if abs(hole['depth_mm'] - part['thickness_mm']) < 0.05 else f"DEPTH {hole['depth_mm']:g}"
        layers.add(layer)
        x = hole['xyz_mm'][long] - part['min'][long]
        y = hole['xyz_mm'][short] - part['min'][short]
        entities += circle(layer, x, y, hole['diameter_mm'])
        face_holes.append(hole)
    entities += text('ANNOTATION', 0, width + 12, f'{name} | {length:g}x{width:g}x{part["thickness_mm"]:g} mm | TEST ONLY')
    if edge_holes:
        entities += text('ANNOTATION', 0, -15, f'{len(edge_holes)} EDGE HOLES: see drilling_review.csv')
    save_dxf(DXF_DIR / f'{name}_FACE_TEST.dxf', entities, layers)
    summary.append({'part': name, 'face_holes': len(face_holes), 'edge_holes': len(edge_holes), 'dxf': f'{name}_FACE_TEST.dxf'})

    # End-grain holes are drawn on their actual entry edge as a second view.
    for axis, sign in sorted({(next(i for i, v in enumerate(h['direction']) if v),
                               next(v for v in h['direction'] if v)) for h in edge_holes}):
        edge_set = [h for h in edge_holes if h['direction'][axis] == sign]
        span = next(i for i in (long, short) if i != axis)
        edge_length = dimensions[span]
        edge_entities = rect('OUTLINE', edge_length, dimensions[thin])
        edge_layers = {'OUTLINE', 'ANNOTATION'}
        for hole in edge_set:
            layer = f"EDGE DEPTH {hole['depth_mm']:g}"
            edge_layers.add(layer)
            x = hole['xyz_mm'][span] - part['min'][span]
            y = hole['xyz_mm'][thin] - part['min'][thin]
            edge_entities += circle(layer, x, y, hole['diameter_mm'])
        edge_entities += text('ANNOTATION', 0, dimensions[thin] + 12,
                              f'{name} EDGE {"XYZ"[axis]}{"+" if sign > 0 else "-"} | TEST ONLY')
        save_dxf(DXF_DIR / f'{name}_EDGE_{"XYZ"[axis]}{"POS" if sign > 0 else "NEG"}_TEST.dxf', edge_entities, edge_layers)

(OUT / 'dxf_index.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print(f'{len(summary)} face DXFs; {sum(row["face_holes"] for row in summary)} face holes; '
      f'{sum(row["edge_holes"] for row in summary)} edge holes')
