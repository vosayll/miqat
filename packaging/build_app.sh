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

# Вкладываем Sparkle.framework (движок авто-обновления) и учим бинарь искать
# фреймворки в Contents/Frameworks. Присутствует только в обычной сборке — в
# App Store-сборке Sparkle не подключается (её собирает build_appstore.sh).
FWSRC="$ROOT/.build/$CONFIG/Sparkle.framework"
if [ -d "$FWSRC" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$FWSRC" "$APP/Contents/Frameworks/Sparkle.framework"
  if install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$NAME" 2>/dev/null; then
    echo "▶︎ вложен Sparkle.framework + rpath @executable_path/../Frameworks"
  else
    echo "▶︎ вложен Sparkle.framework (rpath уже присутствовал)"
  fi
fi

# --- Подпись ---
# Таймстамп нужен только для раздаваемых release-сборок (нотаризация); для
# debug его пропускаем — сетевой TSA-сервер часто подвешивает codesign.
TS=""; [ "$CONFIG" = "release" ] && TS="--timestamp"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"$/\1/')
if [ -n "$IDENTITY" ]; then
  SIGN=(codesign --force --options runtime $TS --sign "$IDENTITY")
  echo "▶︎ подпись Developer ID + hardened runtime:"
  echo "   $IDENTITY"
else
  SIGN=(codesign --force --sign -)
  echo "▶︎ ad-hoc подпись (Developer ID не найден)…"
fi

# Sparkle подписываем ИЗНУТРИ НАРУЖУ: вложенный код (XPC-сервисы, Autoupdate,
# Updater.app) должен быть подписан раньше самого фреймворка, а фреймворк —
# раньше .app. Иначе подпись контейнера будет невалидной.
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  echo "▶︎ подпись компонентов Sparkle…"
  "${SIGN[@]}" "$FW/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
  "${SIGN[@]}" "$FW/Versions/B/Updater.app"
  "${SIGN[@]}" "$FW"
fi

# Сам .app — в самом конце. Без --deep: вложенный код уже подписан поимённо выше,
# а --deep поверх Sparkle ломает подпись XPC-сервисов.
"${SIGN[@]}" "$APP"

echo "✓ готово: $APP"
