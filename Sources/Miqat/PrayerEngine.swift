import Foundation
import Adhan

/// Один намаз в конкретный день (абсолютное время).
struct PrayerSlot: Identifiable {
    let id = UUID()
    let prayer: Prayer
    let name: String
    let time: Date
}

/// Движок расчёта времён намаза.
///
/// ⚙️ Локация и параметры пока ЗАШИТЫ под Грозный и подогнаны под официальную
/// таблицу муфтията ЧР. На M2 сделаем автолокацию + выбор города/метода.
enum PrayerEngine {

    // === Грозный — параметры под таблицу муфтията ЧР =========================
    static let latitude  = 43.3178
    static let longitude = 45.6949
    static let cityName  = "Грозный"
    static let madhab: Madhab = .shafi          // шафиитский Аср

    static let fajrAngle = 14.75                // -> Фаджр 02:37
    static let ishaAngle = 15.65                // -> Иша   21:34

    static let adjustments = PrayerAdjustments(fajr: 0, sunrise: -6, dhuhr: 28,
                                               asr: 8, maghrib: 5, isha: 0)
    // =========================================================================

    static let displayNames: [Prayer: String] = [
        .fajr:    "Fajr",
        .dhuhr:   "Dhuhr",
        .asr:     "Asr",
        .maghrib: "Maghrib",
        .isha:    "Isha",
    ]

    private static let ordered: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func params() -> CalculationParameters {
        var p = CalculationMethod.other.params
        p.fajrAngle = fajrAngle
        p.ishaAngle = ishaAngle
        p.madhab = madhab
        p.adjustments = adjustments
        return p
    }

    private static func prayerTimes(on date: Date) -> PrayerTimes? {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let coords = Coordinates(latitude: latitude, longitude: longitude)
        return PrayerTimes(coordinates: coords, date: comps, calculationParameters: params())
    }

    /// Направление на Киблу (градусы от севера, по часовой).
    static var qiblaDirection: Double {
        Qibla(coordinates: Coordinates(latitude: latitude, longitude: longitude)).direction
    }

    /// Пять намазов на день, к которому относится `date`.
    static func slots(on date: Date = Date()) -> [PrayerSlot] {
        guard let pt = prayerTimes(on: date) else { return [] }
        return ordered.map { prayer in
            PrayerSlot(prayer: prayer, name: displayNames[prayer] ?? "—", time: pt.time(for: prayer))
        }
    }

    /// Следующий намаз. После Иши переходим на Фаджр завтрашнего дня.
    static func next(after now: Date = Date()) -> PrayerSlot? {
        guard let pt = prayerTimes(on: now) else { return nil }
        if let np = pt.nextPrayer(at: now) {
            return PrayerSlot(prayer: np, name: displayNames[np] ?? "—", time: pt.time(for: np))
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        guard let ptTom = prayerTimes(on: tomorrow) else { return nil }
        return PrayerSlot(prayer: .fajr, name: displayNames[.fajr] ?? "Fajr", time: ptTom.time(for: .fajr))
    }

    /// Время предыдущего наступившего намаза (для прогресс-кольца).
    static func previousTime(before now: Date = Date()) -> Date? {
        guard let pt = prayerTimes(on: now) else { return nil }
        if let cur = pt.currentPrayer(at: now) {
            return pt.time(for: cur)
        }
        // до Фаджра — берём вчерашнюю Ишу
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return prayerTimes(on: yesterday)?.time(for: .isha)
    }
}
