Miqat — сборка для App Store (передаётся для подписи и загрузки)
================================================================

Что это
-------
MiqatAppStore.app — вариант приложения для Mac App Store:
  • собран только на ПУБЛИЧНЫХ API (приватных CGS/SkyLight нет — проверено,
    в бинаре 0 приватных символов);
  • App Sandbox включён (entitlements — файл рядом: Miqat.appstore.entitlements);
  • сейчас подписан Developer ID (для проверки локально) — для App Store нужно
    ПЕРЕПОДПИСАТЬ своим Apple Distribution.

Реквизиты
---------
  Bundle id : com.vosayll.miqat
  Team      : 3Y4SDXRXUW
  Мин. macOS: 13.0
  Исходники : github.com/vosayll/miqat  (ветка main) — если удобнее собрать самому:
              bash packaging/build_appstore.sh

Что нужно на аккаунте (разово)
------------------------------
  1. App ID com.vosayll.miqat (Identifiers).
  2. Сертификаты: Apple Distribution + Mac Installer Distribution.
  3. Provisioning-профиль Mac App Store на этот App ID + Apple Distribution.
  4. Запись приложения в App Store Connect (macOS, тот же bundle id).

Подписать, упаковать, залить
----------------------------
  # 1) переподписать приложение под App Store (свой Apple Distribution + профиль)
  cp "путь/к/профилю.provisionprofile" MiqatAppStore.app/Contents/embedded.provisionprofile
  codesign --force --options runtime \
    --entitlements Miqat.appstore.entitlements \
    --sign "Apple Distribution: <ИМЯ> (3Y4SDXRXUW)" \
    MiqatAppStore.app

  # 2) собрать подписанный установщик
  productbuild --component MiqatAppStore.app /Applications \
    --sign "3rd Party Mac Developer Installer: <ИМЯ> (3Y4SDXRXUW)" \
    Miqat.pkg

  # 3) залить (Transporter из Mac App Store: перетащить Miqat.pkg → Deliver;
  #    либо: xcrun altool --upload-app -f Miqat.pkg -t macos -u APPLE_ID -p APP_PW)

Дальше — в App Store Connect выбрать залитый билд, заполнить карточку,
Submit for Review.

Примечание про локскрин: в этой (App Store) версии островок НЕ показывается на
заблокированном экране — это единственное отличие от версии с сайта; так надо,
чтобы пройти ревью (публичные API не умеют рисовать на локскрине).
