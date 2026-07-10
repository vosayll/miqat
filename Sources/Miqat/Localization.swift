import Foundation

/// Язык интерфейса — переключается вручную в настройках (не по системной локали).
enum AppLang: String { case ru, en }

/// Хранит выбранный язык и сохраняет в UserDefaults. По умолчанию — русский.
/// Инжектится в окружение (как ThemeStore): смена языка перерисовывает и шторку,
/// и настройки.
final class LanguageStore: ObservableObject {
    @Published var lang: AppLang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: Self.key) }
    }
    private static let key = "miqat.language"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppLang.ru.rawValue
        lang = AppLang(rawValue: raw) ?? .ru
    }

    var isRU: Bool { lang == .ru }

    /// Строка на текущем языке: t("Настройки", "Settings").
    func t(_ ru: String, _ en: String) -> String { isRU ? ru : en }

    /// Локализованное имя намаза по английскому ключу (Fajr/Dhuhr/…).
    /// Ключи внутри приложения остаются английскими — переводим только показ.
    func prayer(_ english: String) -> String {
        isRU ? Self.prayerRU[english] ?? english : english
    }

    private static let prayerRU: [String: String] = [
        "Fajr": "Фаджр", "Sunrise": "Восход", "Dhuhr": "Зухр",
        "Asr": "Аср", "Maghrib": "Магриб", "Isha": "Иша",
    ]
}
