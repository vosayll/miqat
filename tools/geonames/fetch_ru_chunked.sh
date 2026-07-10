#!/usr/bin/env bash
# Устойчивая загрузка alternateNamesV2.zip кусками по 15 МБ с явными Range —
# длинную загрузку среда рубит, а короткие куски проходят; собираем и фильтруем ru.
set -uo pipefail
cd "$(dirname "$0")"
URL="https://download.geonames.org/export/dump/alternateNamesV2.zip"
TOTAL=$(curl -sI "$URL" | awk 'tolower($1)=="content-length:"{print $2+0}')
echo "полный размер: $TOTAL байт"
CHUNK=15000000
rm -f alt.zip
start=0; idx=0
while [ "$start" -lt "$TOTAL" ]; do
  end=$((start+CHUNK-1)); [ "$end" -ge "$TOTAL" ] && end=$((TOTAL-1))
  want=$((end-start+1)); part="part_$idx"
  ok=0
  for try in 1 2 3 4 5 6; do
    curl -s --range "$start-$end" -o "$part" "$URL"
    have=$(stat -f%z "$part" 2>/dev/null || echo 0)
    if [ "$have" -eq "$want" ]; then ok=1; break; fi
    sleep 2
  done
  [ "$ok" -eq 1 ] || { echo "кусок $idx не докачался"; exit 1; }
  cat "$part" >> alt.zip; rm -f "$part"
  start=$((end+1)); idx=$((idx+1))
  echo "  собрано $((start/1024/1024)) МБ"
done
echo "проверка zip…"
unzip -t alt.zip >/dev/null 2>&1 || { echo "zip битый"; exit 1; }
unzip -o alt.zip >/dev/null
python3 extract_ru.py alternateNamesV2.txt ru_names.tsv
echo "русских имён: $(wc -l < ru_names.tsv)"
grep -P "^558418\t|^524901\t|^745044\t" ru_names.tsv
