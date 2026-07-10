#!/usr/bin/env python3
"""
Из alternateNamesV2.txt (все языки) вытаскивает русские имена городов:
geonameId -> русское название (isolanguage == 'ru', предпочитаем isPreferredName).
Результат — ru_names.tsv для склейки в основной каталог.

Запуск:  python3 extract_ru.py alternateNamesV2.txt ru_names.tsv
"""
import sys

def main(src: str, dst: str) -> None:
    ru: dict[str, str] = {}
    preferred: set[str] = set()
    with open(src, encoding='utf-8') as f:
        for line in f:
            c = line.rstrip('\n').split('\t')
            if len(c) < 4 or c[2] != 'ru':
                continue
            gid, name = c[1], c[3].strip()
            if not name:
                continue
            is_pref = len(c) > 4 and c[4] == '1'
            if gid in preferred:
                continue                      # уже есть предпочтительное — не трогаем
            if is_pref:
                ru[gid] = name; preferred.add(gid)
            elif gid not in ru:
                ru[gid] = name                # первое встреченное, пока нет лучшего
    with open(dst, 'w', encoding='utf-8') as out:
        for gid, name in ru.items():
            out.write(f"{gid}\t{name}\n")
    print(f"русских имён: {len(ru)}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
