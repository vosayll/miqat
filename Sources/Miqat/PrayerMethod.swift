import Foundation

/// Пара «метод расчёта Aladhan + мазхаб для Асра» — что подставить в запрос.
/// method — код метода Aladhan (see /v1/methods), school — 0 Шафии / 1 Ханафи.
struct PrayerMethodChoice: Equatable {
    let method: Int
    let school: Int
}

/// Карта «регион → метод расчёта». Российские муфтияты считают Фаджр/Иша
/// иначе, чем «глобальный» MWL, поэтому для РФ берём метод 14 (ДУМ России:
/// Фаджр 16° / Иша 15°), а мазхаб — по региону (Кавказ шафиитский, остальная
/// Россия ханафитская). Для прочих стран — ближайший региональный метод.
enum PrayerMethod {

    /// Дефолт, когда страну определить не удалось. Основная аудитория — РФ.
    static let fallback = PrayerMethodChoice(method: 14, school: 0)

    // Коды методов Aladhan (сверено на /v1/methods).
    private static let RUSSIA = 14   // ДУМ России (Фаджр 16° / Иша 15°)
    private static let TURKEY = 13   // Diyanet
    private static let MAKKAH = 4    // Умм аль-Кура
    private static let EGYPT  = 5    // Египетское управление
    private static let TEHRAN = 7    // Тегеран
    private static let DUBAI  = 16
    private static let KUWAIT = 9
    private static let QATAR  = 10
    private static let ISNA   = 2    // Северная Америка
    private static let MWL    = 3    // Всемирная исламская лига (глобальный)

    /// Регионы Северного Кавказа, где преобладает шафиитский мазхаб.
    /// Сверяем с CLPlacemark.administrativeArea (нормализуем регистр/пробелы).
    private static let caucasusShafiiKeywords: [String] = [
        "чечен", "chechn",              // Чечня
        "дагестан", "dagestan",         // Дагестан
        "ингушет", "ingush",            // Ингушетия
        "кабардино", "kabardino",       // Кабардино-Балкария
        "карачаево", "karachay",        // Карачаево-Черкесия
        "осети", "ossetia",             // Северная Осетия
        "адыге", "adyg",                // Адыгея
    ]

    /// Разрешение «авто»: по ISO-коду страны и региону (administrativeArea)
    /// из reverse-geocode. Оба опциональны — при нехватке данных работает фолбэк.
    ///
    /// - Parameters:
    ///   - countryCode: ISO-код страны placemark.isoCountryCode ("RU", "TR", …).
    ///   - administrativeArea: регион placemark.administrativeArea (для РФ — субъект).
    static func choice(countryCode: String?, administrativeArea: String?) -> PrayerMethodChoice {
        guard let code = countryCode?.uppercased() else { return fallback }
        switch code {
        case "RU":
            // Метод один (ДУМ России), мазхаб — по региону.
            let school = isCaucasusShafii(administrativeArea) ? 0 : 1
            return PrayerMethodChoice(method: RUSSIA, school: school)
        case "TR": return PrayerMethodChoice(method: TURKEY, school: 0)
        case "SA": return PrayerMethodChoice(method: MAKKAH, school: 0)
        case "EG": return PrayerMethodChoice(method: EGYPT,  school: 0)
        case "IR": return PrayerMethodChoice(method: TEHRAN, school: 0)
        case "AE": return PrayerMethodChoice(method: DUBAI,  school: 0)
        case "KW": return PrayerMethodChoice(method: KUWAIT, school: 0)
        case "QA": return PrayerMethodChoice(method: QATAR,  school: 0)
        case "US", "CA": return PrayerMethodChoice(method: ISNA, school: 0)
        default: return PrayerMethodChoice(method: MWL, school: 0)   // глобальный
        }
    }

    /// Кавказский (шафиитский) регион РФ? Фолбэк при пустом регионе — шафии (false).
    static func isCaucasusShafii(_ administrativeArea: String?) -> Bool {
        guard let area = administrativeArea?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !area.isEmpty else { return true }   // регион неизвестен → шафии (см. промт)
        return caucasusShafiiKeywords.contains { area.contains($0) }
    }
}
