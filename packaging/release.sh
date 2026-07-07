#!/usr/bin/env bash
# Собирает НОТАРИЗОВАННЫЙ Miqat.dmg (подпись Developer ID + hardened runtime +
# нотаризация Apple + staple). Открывается на любом Маке без предупреждений.
#
# Требует один раз настроенного:
#   • сертификат «Developer ID Application» в связке ключей;
#   • сохранённый профиль notarytool «miqat-notary»
#     (xcrun notarytool store-credentials "miqat-notary" --apple-id … --team-id … --password …)
#
# Использование:  bash packaging/release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Miqat.app"
DMG="$ROOT/Miqat.dmg"
PROFILE="miqat-notary"

echo "▶︎ 1/5 сборка + подпись Developer ID (hardened runtime)…"
bash "$ROOT/packaging/build_app.sh" release

echo "▶︎ 2/5 нотаризация приложения…"
ZIP="$ROOT/.miqat-notarize.zip"
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$ZIP"

echo "▶︎ 3/5 staple приложения…"
xcrun stapler staple "$APP"

echo "▶︎ 4/5 сборка .dmg…"
STAGE="$ROOT/packaging/dmg_stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Miqat.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Miqat" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▶︎ 5/5 подпись + нотаризация + staple .dmg…"
IDENTITY=$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"$/\1/')
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "✓ Готово: $DMG"
spctl -a -vvv --type open --context context:primary-signature "$DMG" 2>&1 | tail -3
