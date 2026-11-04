#!/usr/bin/env python3
"""Bundle the AC Station test scene, Viyar parts CSV and inspection drawings."""
import csv
import json
import shutil
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path('M:/projects/furniture/AC-Station')
out = root / 'exports' / 'viyar_test_20261104'
scene = root / 'cad' / 'sketchup' / 'AC_Station_v4_banding_drilling_TEST.skp'
source_csv = root / 'manufacturing' / 'viyar_import_alder_18mm_DRAFT.csv'
parts_csv = out / 'viyar_parts_edges_TEST.csv'
shutil.copyfile(source_csv, parts_csv)

manifest = json.loads((out / 'drilling_manifest.json').read_text(encoding='utf-8'))
qa = json.loads((out / 'scene_qa.json').read_text(encoding='utf-8'))
with parts_csv.open(encoding='utf-8-sig', newline='') as fh:
    part_rows = list(csv.DictReader(fh, delimiter=';'))
with (out / 'drilling_review.csv').open(encoding='utf-8-sig', newline='') as fh:
    hole_rows = list(csv.DictReader(fh, delimiter=';'))
assert len(part_rows) == qa['part_count'] == 15
assert len(hole_rows) == qa['hole_count'] == len(manifest['holes']) == 26
assert qa['all_manifold'] and not qa['modified']
assert len(list((out / 'dxf_drawings').glob('*.dxf'))) == 17
assert scene.is_file() and scene.stat().st_size > 100_000

readme = '''# AC Station v4 — пробний комплект для ViyarPro

**Статус: ТЕСТ. Не оформлювати замовлення з цих файлів без перевірки отворів і фурнітури.**

## Що відкрити

1. `AC_Station_v4_banding_drilling_TEST.skp` — окрема копія 3D-сцени. У 15 деталях ЛДСП є 26 фізично вирізаних отворів; торці пофарбовані матеріалами крайки OpenCutList. Вихідний OCL Draft не змінено.
2. `preview_TEST.png` — швидкий огляд лицевих проекцій: синя лінія = номінальна крайка 0,5 мм (артикул 125349, фактично 0,45 мм), зелена = 2 мм (125353), червоні кола = отвори в пласть. Торцеві отвори дивіться в окремих DXF.
3. `viyar_parts_edges_TEST.csv` — **імпорт у розділ плитних деталей ViyarPro** для розкрою й крайки. Виберіть ЛДСП 49004; індекс крайки 1 зіставте з 125349, індекс 2 — з 125353. Звірте пильні й готові розміри та текстуру всіх 15 рядків. Цей CSV не переносить свердління.
4. `drilling_review.csv` — 26 операцій зі стороною, координатами у світових осях і від мінімального кута деталі, Ø та глибиною. Це контрольний список для ручного внесення та звірки. **Не завантажуйте його як CSV деталей.**
5. `dxf_drawings/*_FACE_TEST.dxf` — окремі 2D-креслення кожної плити у мм із колами фізичних отворів у пласть. `*_EDGE_*_TEST.dxf` — торцеві види боковин з чотирма пілотними отворами. Шари `DEPTHF`, `DEPTH <мм>` і `EDGE DEPTH <мм>` зроблені для пробного імпорту. Це **не підтверджений ABF_Flatten/DXF формат Viyar**; повідомте, що саме прийняв або відхилив імпортер.

## Як тестувати у Viyar

Спочатку імпортуйте `viyar_parts_edges_TEST.csv` у «Плитні матеріали → Деталі → Імпорт із текстового файлу». Перевірте матеріал, крайку, орієнтацію й розміри. DXF завантажуйте **в окремий пробний проєкт**, починаючи з `Drawer_Front_Wall_FACE_TEST.dxf` або `Drawer_Left_FACE_TEST.dxf`. Звірте, чи Viyar створив операції свердління з правильного боку, а не лише плоске креслення. Якщо імпорт не приймає DXF, 3D `.skp` і `drilling_review.csv` залишаються контрольними файлами для нативного внесення отворів.

## Що ще потрібно звірити

- Отвори напрямних 400 мм, цинк побудовані за координатами з наданих схем як **тестове трактування**. Відповідність саме Viyar 52504, шурупи, монтажну висоту 21 мм і передній відступ потрібно перевірити на реальній напрямній/кресленні.
- Фасад: два кріплення; Ø5 наскрізь через передню стінку, Ø5 × 12 мм глухо у фасад. Тип кріплення фасаду й посадку голівки ще не вибрано.
- Стики дна з боковинами: чотири конфірмати 7×50 з пілотними отворами Ø5. Профіль і зенківка попередні.
- Шість деталей шириною 50 мм не просвердлені: вони не проходять опублікований мінімум ширини 70 мм послуги CNC-свердління Viyar. Стики верхніх підсилювачів і бортиків ще потребують окремого рішення.
- 9-мм фанерне дно шухляди не входить до CSV ЛДСП і потребує окремого матеріалу/замовлення.

Джерела: https://www.viyar.pro/service/doc/?cid=dsp&s=details-import ; https://www.viyar.pro/service/doc/?cid=dsp&s=limitations ; https://docs.opencutlist.org/features/smart-export-tool
'''
(out / 'README_TEST_UA.md').write_text(readme, encoding='utf-8')

bundle = out / 'AC_Station_v4_Viyar_TEST_bundle.zip'
with ZipFile(bundle, 'w', ZIP_DEFLATED) as archive:
    archive.write(scene, scene.name)
    for path in sorted(out.rglob('*')):
        if path.is_file() and path != bundle:
            archive.write(path, path.relative_to(out))
with ZipFile(bundle) as archive:
    assert archive.testzip() is None
print(bundle)
