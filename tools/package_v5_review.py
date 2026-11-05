"""Package checked local drawings; no claim of Viyar machining compatibility."""
from pathlib import Path
import csv
import json
import shutil
from zipfile import ZipFile, ZIP_DEFLATED
root=Path('M:/projects/furniture/AC-Station')
out=root/'exports/viyar_test_20261105'
data=json.loads((out/'drilling_manifest.json').read_text(encoding='utf-8'))
assert len(data['parts']) == 15 and len(data['holes']) == 42
shutil.copy2(root/'exports/viyar_test_20261104/viyar_parts_edges_TEST.csv',out/'viyar_parts_edges_TEST.csv')
rows=[
 ['Конфірмат 7x50: дно-корпус',4,'шт','Профіль попередній; зенківку перевірити'],
 ['Конфірмат 7x50: кути шухляди',8,'шт','Отвори додані; потрібна зенківка під рейкою'],
 ['Напрямна 400 мм цинк, кандидат 52504',1,'комплект','Монтажну схему та кріпильні гвинти звірити'],
 ['Кріпильний гвинт напрямної',14,'шт','14 отворів за поточним планом; тип гвинта не обрано'],
 ['Кріплення фасаду',2,'шт','Артикул не обрано; отвори попередні'],
 ['Опора / колесо',4,'шт','Артикул і схема монтажної пластини відсутні'],
 ['Кріплення дна шухляди','','','Тип і кількість не визначені'],
 ['Кріплення верхньої платформи, царг, ребра й бортиків','','','Тип і кількість не визначені'],
 ['ЛДСП 18 мм, 49004',15,'деталей','Крайка у CSV деталей'],
 ['Фанерне дно 9 мм, 499x400',1,'деталь','Матеріал не обрано; окремо від CSV ЛДСП'],
]
with (out/'hardware_bom_REVIEW.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f,delimiter=';');w.writerow(['Назва','Кількість','Одиниця','Стан']);w.writerows(rows)
(out/'README_UA.md').write_text('''# AC Station v5 — огляд присадки

Додано 4 кутові з’єднання шухляди: 8 конфірматів і 16 фізичних отворів. Разом у моделі 42 отвори.
Це ще НЕ повна виробнича комплектація. Відкриті позиції перелічені в hardware_bom_REVIEW.csv; порожня кількість означає невизначену позицію, а не нуль.

## Файли й призначення

- AC_Station_v5_drawer_joints_TEST.skp — геометрія плит з фізичними отворами.
- AC_Station_v5_TECHNICAL_REVIEW.skp — кольоровий огляд, 3 сцени; допоміжні сині осі не є фурнітурою.
- viyar_parts_edges_TEST.csv — імпорт розкрою та крайки у розділ плитних матеріалів ViyarPro. Свердлінь і просторової збірки у CSV немає.
- dxf_drawings — контрольні креслення. Їх не можна вважати готовим форматом присадки ViyarPro.
- drilling_review.csv — координати, сторона, діаметр і глибина 42 отворів.
- hardware_bom_REVIEW.csv — кількості відомих кріплень і невизначені позиції.

## Чому DXF не створив меблі на сайті

На наданому користувачем скрині DXF додано в «3D обміри» конструктора меблів. Це довідкова геометрія, а не деталі меблевого виробу. Команда «Експорт у ViyarPro» існує для нативного виробу конструктора. Спробу її перевірити 05.11.2026 зупинило повідомлення сайту про завершену сесію. Відкритий каталожний комод має 4 шухляди та не є нашою AC Station.

## Команди Zilla 0.5

Виділити збірку → Extensions → Zilla Furniture Tools — Drawer box: 4 corner joints. Команда створює знімні мітки на чотирьох стінках, а не автоматично затверджує виробництво. Smart Joint тепер працює і з деталями шухляди. Drill selected guides in new SKP вирізає вибрані мітки у новій копії.

Не запускати повторне вирізання тих самих отворів у вже просвердленому файлі. Для повторного планування використовувати чистий вихідний файл.
''',encoding='utf-8')
with ZipFile(out/'AC_Station_v5_REVIEW.zip','w',ZIP_DEFLATED) as z:
 for path in out.rglob('*'):
  if path.is_file() and path.suffix!='.zip':z.write(path,path.relative_to(out))
 for name in ['AC_Station_v5_drawer_joints_TEST.skp','AC_Station_v5_TECHNICAL_REVIEW.skp']:
  z.write(root/'cad/sketchup'/name,name)
print(out/'AC_Station_v5_REVIEW.zip')
