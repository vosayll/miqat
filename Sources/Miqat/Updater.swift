import Foundation

// Авто-обновление для сборки, которую раздаём напрямую (.dmg мимо App Store,
// через свою ленту appcast). В App Store-сборке Sparkle НЕ подключается
// (Package.swift не добавляет зависимость под MIQAT_APPSTORE) — там обновления
// ставит сам App Store. Поэтому весь файл выключен флагом APPSTORE.
#if !APPSTORE
import Sparkle

/// Тонкая обёртка над Sparkle. Держит апдейтер с НАШИМ драйвером интерфейса
/// (MiqatUpdaterUI — красивая обработка ошибок) и делегата, который умеет на
/// время локального теста подменить адрес ленты обновлений.
@MainActor
final class UpdaterManager: NSObject {
    private let updater: SPUUpdater
    private let userDriver: MiqatUpdaterUI
    // Sparkle держит ссылку на делегата слабой — сохраняем его сами.
    private let feedDelegate: FeedOverrideDelegate

    override init() {
        let host = Bundle.main
        let driver = MiqatUpdaterUI(hostBundle: host)
        let delegate = FeedOverrideDelegate()
        userDriver = driver
        feedDelegate = delegate
        updater = SPUUpdater(hostBundle: host, applicationBundle: host,
                             userDriver: driver, delegate: delegate)
        super.init()
        do {
            // Запускает фоновые проверки по расписанию (интервал и разрешение —
            // из Info.plist: SUEnableAutomaticChecks / SUScheduledCheckInterval).
            try updater.start()
        } catch {
            NSLog("[Miqat/Updater] startUpdater failed: %@", String(describing: error))
        }
    }

    /// Ручная проверка из пункта меню «Проверить обновления…».
    func checkForUpdates() {
        updater.checkForUpdates()
    }
}

/// На время локального теста позволяет указать свою ленту обновлений через
/// переменную окружения MIQAT_FEED_URL (например
/// http://localhost:8000/appcast.xml), не трогая боевой SUFeedURL в Info.plist.
/// В обычном запуске возвращает nil — тогда Sparkle берёт адрес из Info.plist.
final class FeedOverrideDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        if let override = ProcessInfo.processInfo.environment["MIQAT_FEED_URL"],
           !override.isEmpty {
            NSLog("[Miqat/Updater] feed override → %@", override)
            return override
        }
        return nil
    }
}
#endif
