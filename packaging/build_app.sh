#!/usr/bin/env bash
# Собирает SPM-бинарь и заворачивает его в настоящий Miqat.app
# (с Info.plist и ad-hoc подписью — чтобы система дала «взрослые» права, напр. геолокацию).
#
# Использование:  bash packaging/build_app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Miqat.app"
NAME="Miqat"

echo "▶︎ swift build ($CONFIG)…"
swift build --package-path "$ROOT" -c "$CONFIG"
BIN="$ROOT/.build/$CONFIG/$NAME"

echo "▶︎ собираю $NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ресурсный бандл SPM (каталог городов и пр.) — Bundle.module ищет его в Resources.
BUNDLE="$ROOT/.build/$CONFIG/Miqat_Miqat.bundle"
if [ -d "$BUNDLE" ]; then
  cp -R "$BUNDLE" "$APP/Contents/Resources/"
  echo "▶︎ вложен ресурсный бандл: $(basename "$BUNDLE")"
fi

# Таймстамп нужен только для раздаваемых release-сборок (нотаризация); для
# debug его пропускаем — сетевой TSA-сервер часто подвешивает codesign.
TS=""; [ "$CONFIG" = "release" ] && TS="--timestamp"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"$/\1/')
if [ -n "$IDENTITY" ]; then
  echo "▶︎ подпись Developer ID + hardened runtime:"
  echo "   $IDENTITY"
  codesign --force --options runtime $TS --sign "$IDENTITY" "$APP"
else
  echo "▶︎ ad-hoc подпись (Developer ID не найден)…"
  codesign --force --deep --sign - "$APP"
fi

echo "✓ готово: $APP"
