#!/usr/bin/env bash
# Сборка варианта для App Store: только публичные API (флаг MIQAT_APPSTORE=1).
# Пакет SkyLightWindow и приватные обёртки (CGSSpace/SkyLightLock) не подключаются.
# После сборки проверяет, что в бинаре НЕТ приватных символов CGS/SkyLight —
# именно на них Apple заворачивает при review.
#
# Собирается в отдельную папку .build-appstore, чтобы не путать с обычной сборкой.
# Полная выкладка в App Store (провижининг, сэндбокс, upload) требует твоего
# аккаунта Apple Developer и делается отдельно — этот скрипт готовит и проверяет
# «чистый» бинарь.
#
# Использование:  bash packaging/build_appstore.sh
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="$ROOT/.build-appstore"
NAME="Miqat"

echo "▶︎ swift build (release, MIQAT_APPSTORE=1)…"
MIQAT_APPSTORE=1 swift build --package-path "$ROOT" -c release --scratch-path "$SCRATCH"
BIN="$SCRATCH/release/$NAME"

echo "▶︎ проверка бинаря на приватные символы…"
PATTERN='CGSSpaceCreate|CGSSpaceDestroy|CGSAddWindowsToSpaces|CGSRemoveWindowsFromSpaces|CGSSpaceSetAbsoluteLevel|CGSShowSpaces|CGSHideSpaces|_CGSDefaultConnection|SLSRemoveWindowsFromSpaces|PrivateFrameworks/SkyLight'
BAD_SYM=$(nm -u "$BIN" 2>/dev/null | grep -iE "$PATTERN" || true)
BAD_STR=$(strings - "$BIN" 2>/dev/null | grep -iE "$PATTERN" || true)
if [ -n "$BAD_SYM$BAD_STR" ]; then
  echo "✗ НАЙДЕНЫ приватные символы/строки — App Store завернёт:"
  [ -n "$BAD_SYM" ] && echo "  символы: $BAD_SYM"
  [ -n "$BAD_STR" ] && echo "  строки:  $BAD_STR"
  exit 1
fi
echo "✓ приватных символов CGS/SkyLight в бинаре нет"
echo "✓ App Store-бинарь готов: $BIN"
