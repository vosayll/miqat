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

# Заворачиваем в запускаемый MiqatAppStore.app (отдельно от обычного Miqat.app,
# чтобы можно было гонять оба варианта и сравнивать). Подпись — Developer ID,
# если есть (как в обычной сборке), иначе ad-hoc: локально запустить хватит.
# Настоящая выкладка в App Store подписывается отдельно (App Sandbox + провижининг).
APP="$ROOT/MiqatAppStore.app"
echo "▶︎ собираю MiqatAppStore.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Подписываем С App Sandbox entitlements — как потребует App Store. Сэндбокс
# работает и с ad-hoc подписью, так что локальный запуск честно проверяет,
# что островок/мониторы/сеть/геолокация не ломаются в песочнице.
ENT="$ROOT/packaging/Miqat.appstore.entitlements"
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"$/\1/')
if [ -n "$IDENTITY" ]; then
  echo "▶︎ подпись Developer ID + hardened runtime + App Sandbox…"
  codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$IDENTITY" "$APP"
else
  echo "▶︎ ad-hoc подпись + App Sandbox…"
  codesign --force --entitlements "$ENT" --sign - "$APP"
fi
echo "✓ App Store-приложение готово (в песочнице): $APP"
echo "▶︎ проверка entitlements:"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -iE "sandbox|network|location" || true
