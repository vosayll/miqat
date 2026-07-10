#!/usr/bin/env python3
"""
Устойчивая загрузка alternateNamesV2.zip: дописываем файл от его реального
размера, переподключаясь каждые ~8 МБ. Среда рубит длинные соединения — а тут
каждое короткое, прогресс всегда сохраняется (докачка по Range). Затем ru-фильтр.
"""
import urllib.request, os, sys, time

URL = "https://download.geonames.org/export/dump/alternateNamesV2.zip"
OUT = os.path.join(os.path.dirname(__file__), "alt.zip")
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17 Safari/605.1.15"}

def total_size() -> int:
    req = urllib.request.Request(URL, headers=UA, method="HEAD")
    return int(urllib.request.urlopen(req, timeout=30).headers["Content-Length"])

def main():
    total = total_size()
    print(f"полный размер: {total} байт", flush=True)
    stalls = 0
    while True:
        have = os.path.getsize(OUT) if os.path.exists(OUT) else 0
        if have >= total:
            break
        req = urllib.request.Request(URL, headers={**UA, "Range": f"bytes={have}-"})
        try:
            resp = urllib.request.urlopen(req, timeout=60)
            code = resp.getcode()
            if have > 0 and code != 206:          # сервер не уважил Range — начать заново
                os.remove(OUT); continue
            written = 0
            with open(OUT, "ab") as f:
                while written < 8_000_000:
                    block = resp.read(65536)
                    if not block:
                        break
                    f.write(block); written += len(block)
            stalls = 0 if written else stalls + 1
            if stalls > 8:
                print("нет прогресса, стоп"); sys.exit(1)
        except Exception as e:
            print(f"  повтор ({e})", flush=True); time.sleep(2)
        print(f"  {os.path.getsize(OUT)//1024//1024} / {total//1024//1024} МБ", flush=True)
    print("готово, размер совпал", flush=True)

if __name__ == "__main__":
    main()
