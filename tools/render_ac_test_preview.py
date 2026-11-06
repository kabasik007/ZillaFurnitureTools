#!/usr/bin/env python3
"""Render a compact inspection sheet from the AC Station test manifest."""
import json
import csv
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out = Path('M:/projects/furniture/AC-Station/exports/viyar_test_20261104')
data = json.loads((out / 'drilling_manifest.json').read_text(encoding='utf-8'))
parts = data['parts']
with (Path('M:/projects/furniture/AC-Station/manufacturing/edge_plan_draft.csv')).open(encoding='utf-8-sig', newline='') as fh:
    edges_by_name = {r['Деталь']: r for r in csv.DictReader(fh, delimiter=';')}
width, height = 1500, 1600
image = Image.new('RGB', (width, height), '#f5f5f1')
draw = ImageDraw.Draw(image)
font_path = 'C:/Windows/Fonts/arial.ttf'
font = ImageFont.truetype(font_path, 21)
small = ImageFont.truetype(font_path, 16)
draw.text((32, 18), 'AC STATION V4  |  TEST DRILLING + EDGE BANDING', fill='#222222', font=font)
draw.text((32, 50), '15 boards / 26 physical holes. 50 mm rails and stops: no drilling. Verify every part in Viyar.', fill='#884422', font=small)
draw.text((1000, 50), 'Edge: blue 0.5 mm / green 2 mm', fill='#286356', font=small)
for index, part in enumerate(parts):
    col, row = index % 3, index // 3
    ox, oy = 32 + col * 490, 88 + row * 290
    draw.rounded_rectangle((ox, oy, ox + 465, oy + 265), radius=8, outline='#b1b5b3', width=2, fill='white')
    dims = part['dims_mm']
    thin = part['thickness_axis']
    long, short = sorted((a for a in range(3) if a != thin), key=lambda a: -dims[a])
    length, board_width = dims[long], dims[short]
    scale = min(410 / length, 175 / board_width)
    x0, y0 = ox + 24, oy + 56
    x1, y1 = x0 + length * scale, y0 + board_width * scale
    draw.rectangle((x0, y0, x1, y1), fill='#d3a071', outline='#73543a', width=2)
    edge_row = edges_by_name[part['name']]
    edge_segments = [
        ('Крайка В мм', (x0, y1, x1, y1)),
        ('Крайка Н мм', (x0, y0, x1, y0)),
        ('Крайка Л мм', (x0, y0, x0, y1)),
        ('Крайка П мм', (x1, y0, x1, y1)),
    ]
    for field, segment in edge_segments:
        value = float(edge_row[field])
        if value:
            draw.line(segment, fill='#1471d0' if value < 1 else '#168153', width=5)
    holes = [h for h in data['holes'] if h['part_name'] == part['name']]
    face_holes = 0
    for hole in holes:
        axis = next(a for a, v in enumerate(hole['direction']) if v)
        if axis != thin:
            continue
        x = x0 + (hole['xyz_mm'][long] - part['min'][long]) * scale
        y = y0 + (hole['xyz_mm'][short] - part['min'][short]) * scale
        r = max(3, hole['diameter_mm'] * scale / 2)
        draw.ellipse((x-r, y-r, x+r, y+r), fill='white', outline='#bb2233', width=2)
        face_holes += 1
    draw.text((ox + 14, oy + 11), part['name'], fill='#222222', font=font)
    draw.text((ox + 14, oy + 235), f'{length:g} x {board_width:g} x {part["thickness_mm"]:g} mm   |   face {face_holes} / edge {len(holes)-face_holes}',
              fill='#555555', font=small)
image.save(out / 'preview_TEST.png')
print(out / 'preview_TEST.png')
