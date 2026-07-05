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

echo "▶︎ ad-hoc подпись…"
codesign --force --deep --sign - "$APP"

echo "✓ готово: $APP"
