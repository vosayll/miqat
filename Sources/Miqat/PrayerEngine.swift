import Foundation
import CoreLocation
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
/// Локация теперь динамическая (обновляется геолокацией). Рядом с Грозным —
/// точная калибровка под муфтият ЧР; в других городах — стандартный метод (MWL).
/// Выбор метода/города в настройки вынесем позже (M2, шаг 4).
enum PrayerEngine {

    /// Фоллбэк-локация, пока геолокация не отдала координаты.
    static let grozny = CLLocationCoordinate2D(latitude: 43.3178, longitude: 45.6949)

    /// Текущая локация и город (обновляются из LocationProvider).
    static var coordinate = grozny
    static var cityName = "Грозный"

    static let madhab: Madhab = .shafi          // шафиитский Аср

    static let displayNames: [Prayer: String] = [
        .fajr:    "Fajr",
        .dhuhr:   "Dhuhr",
        .asr:     "Asr",
        .maghrib: "Maghrib",
        .isha:    "Isha",
    ]

    private static let ordered: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    /// Рядом ли с Грозным (~60 км) — тогда применяем калибровку муфтията.
    private static func isNearGrozny(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: grozny.latitude, longitude: grozny.longitude)) < 60_000
    }

    private static func params() -> CalculationParameters {
        if isNearGrozny(coordinate) {
            // Точная калибровка под таблицу муфтията ЧР.
            var p = CalculationMethod.other.params
            p.fajrAngle = 14.75
            p.ishaAngle = 15.65
            p.madhab = madhab
            p.adjustments = PrayerAdjustments(fajr: 0, sunrise: -6, dhuhr: 28,
                                              asr: 8, maghrib: 5, isha: 0)
            return p
        } else {
            // Прочие города — стандартный метод (пока без ручного выбора).
            var p = CalculationMethod.muslimWorldLeague.params
            p.madhab = madhab
            return p
        }
    }

    private static func prayerTimes(on date: Date) -> PrayerTimes? {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let coords = Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return PrayerTimes(coordinates: coords, date: comps, calculationParameters: params())
    }

    /// Направление на Киблу (градусы от севера, по часовой).
    static var qiblaDirection: Double {
        Qibla(coordinates: Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)).direction
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
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return prayerTimes(on: yesterday)?.time(for: .isha)
    }
}
