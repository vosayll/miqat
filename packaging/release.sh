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

# ─── Публикация на miqat.space (Sparkle appcast + .dmg) ───────────────────────
# Выполняется, ТОЛЬКО если заданы ключ подписи Sparkle и FTP-пароль — иначе просто
# оставляем собранный .dmg. Задать один раз (напр. в ~/.zshrc):
#   export MIQAT_SPARKLE_KEY="$HOME/.miqat/sparkle-key"   # приватный EdDSA-ключ (chmod 600)
#   export MIQAT_FTP_PASS="…"                              # пароль FTP Sweb
# После этого выпуск новой версии = поднять версию в Info.plist + запустить этот скрипт.
KEYFILE="${MIQAT_SPARKLE_KEY:-$HOME/.miqat/sparkle-key}"
if [ -f "$KEYFILE" ] && [ -n "${MIQAT_FTP_PASS:-}" ]; then
  echo "▶︎ appcast + публикация на miqat.space…"
  STAGE="$ROOT/.appcast-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp "$DMG" "$STAGE/Miqat.dmg"
  # Ключ читаем из файла (не из Keychain) — чтобы не ловить диалоги доступа.
  "$ROOT/Vendor/sparkle/bin/generate_appcast" --ed-key-file "$KEYFILE" \
      --download-url-prefix "https://miqat.space/" "$STAGE" >/dev/null
  FTP="ftp://wols201562_1:${MIQAT_FTP_PASS}@77.222.40.251/public_html"
  curl -sS -T "$STAGE/Miqat.dmg"   "$FTP/Miqat.dmg"   -w "  Miqat.dmg → HTTP %{http_code}\n"
  curl -sS -T "$STAGE/appcast.xml" "$FTP/appcast.xml" -w "  appcast.xml → HTTP %{http_code}\n"
  rm -rf "$STAGE"
  echo "✓ Опубликовано: https://miqat.space/Miqat.dmg + appcast.xml"
else
  echo "ⓘ Публикация пропущена (нет файла MIQAT_SPARKLE_KEY или переменной MIQAT_FTP_PASS)."
  echo "  Собранный .dmg лежит здесь: $DMG"
fi
