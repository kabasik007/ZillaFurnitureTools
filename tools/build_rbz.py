#!/usr/bin/env python3
"""Build a .rbz for SketchUp Extension Manager from the repository root."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'dist' / 'ZillaFurnitureTools-v0.3.0.rbz'
FILES = ['zillafurnituretools.rb', 'zillafurnituretools/main.rb',
         'zillafurnituretools/planner.rb', 'zillafurnituretools/hardware.rb',
         'zillafurnituretools/mounting.rb',
         'zillafurnituretools/smart_joint.rb', 'zillafurnituretools/smart_joint.html',
         'zillafurnituretools/ui.html']
OUTPUT.parent.mkdir(exist_ok=True)
with ZipFile(OUTPUT, 'w', ZIP_DEFLATED) as archive:
    for name in FILES:
        archive.write(ROOT / name, arcname=name)
print(OUTPUT)
