#!/usr/bin/env python3
"""
Собирает компактный каталог городов для Miqat из дампа GeoNames (cities5000.txt).

Из ~19 колонок GeoNames оставляем только нужное приложению и одно русское имя
(для поиска кириллицей). Результат — TSV, который приложение читает в память
на старте: geonameId + координаты + пояс дают всё для адреса файла Sajda и для
поиска/ближайшего города.

Колонки на выходе (TSV):
  id  name  ascii  ru  lat  lon  country  admin1  tz  population

Запуск:  python3 build_catalog.py cities5000.txt ../../Sources/Miqat/Resources/cities.tsv
"""
import sys

def load_ru(path: str) -> dict:
    """geonameId -> русское имя (из extract_ru.py, языковые метки GeoNames)."""
    ru = {}
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                gid, name = line.rstrip('\n').split('\t', 1)
                ru[gid] = name
    except FileNotFoundError:
        pass
    return ru

def clean(s: str) -> str:
    return s.replace('\t', ' ').replace('\n', ' ').strip()

def main(src: str, dst: str, ru_path: str = "") -> None:
    ru_map = load_ru(ru_path) if ru_path else {}
    rows = []
    with open(src, encoding='utf-8') as f:
        for line in f:
            col = line.rstrip('\n').split('\t')
            if len(col) < 18:
                continue
            gid, name, ascii_ = col[0], col[1], col[2]
            lat, lon = col[4], col[5]
            country, admin1 = col[8], col[10]
            population, tz = col[14], col[17]
            try:
                pop = int(population or 0)
            except ValueError:
                pop = 0
            ru = ru_map.get(gid, "")
            rows.append((gid, clean(name), clean(ascii_), clean(ru),
                         lat, lon, country, admin1, tz, str(pop)))
    # По убыванию населения — поиск сразу выдаёт крупные города первыми.
    rows.sort(key=lambda r: int(r[9]), reverse=True)
    with open(dst, 'w', encoding='utf-8') as out:
        for r in rows:
            out.write('\t'.join(r) + '\n')
    print(f"городов записано: {len(rows)}")
    print(f"файл: {dst}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
